// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Rupaj Sen

import AppKit
import SMCKit
import SwiftUI

final class FanModel: ObservableObject {
    struct Fan: Identifiable {
        let id: Int
        let name: String
        var rpm = 0.0
        var minimum = 0.0
        var maximum = 1.0
        var automaticTarget = 0.0
        var isManual = false
        var target = 0.0
        var floor = 0.0
    }

    struct Reading: Identifiable {
        let name: String
        let celsius: Int
        var id: String { name }
    }

    enum Availability { case checking, noFans, unsupported, needsHelper, helperOutdated, ready }
    enum Mode { case automatic, manual, max }

    @Published private(set) var fans: [Fan] = []
    @Published private(set) var readings: [Reading] = []
    @Published private(set) var availability: Availability = .checking
    @Published private(set) var fallbackReason: String?
    @Published private(set) var isEngaging = false
    private(set) var isExperimental = MacModel.current?.isFanControlExperimental ?? false
    @Published private(set) var isChangingHelper = false
    @Published private(set) var helperError: String?

    /// Called when the helper put the fans back on automatic without being asked.
    var onReverted: (() -> Void)?

    var isManual: Bool { fans.contains(where: \.isManual) }

    var mode: Mode {
        guard isManual else { return .automatic }
        return fans.allSatisfy { $0.isManual && $0.target >= $0.maximum - 1 } ? .max : .manual
    }

    var averageRPM: Double {
        guard !fans.isEmpty else { return 0 }
        return fans.reduce(0) { $0 + $1.rpm } / Double(fans.count)
    }

    private let queue = DispatchQueue(label: "notchutils.fans")
    private var smc: SMC?
    private var canControl = false
    private var temperatureKeys: [(name: String, keys: [String])]?
    private var isVisible = false
    private var pollTimer: Timer?
    private var keepAliveTimer: Timer?
    private var pendingSet: [Int: DispatchWorkItem] = [:]

    init() {
        #if !DEMO
        queue.async { [self] in
            smc = SMC()
            let count = smc.map(FanSupport.fanCount) ?? 0
            canControl = smc.map { FanSupport.canControl($0) } ?? false
            let names: [String]
            switch count {
            case 1: names = ["Fan"]
            case 2: names = ["Left fan", "Right fan"]
            default: names = (0..<count).map { "Fan \($0 + 1)" }
            }
            let initial = names.enumerated().map { Fan(id: $0.offset, name: $0.element) }
            DispatchQueue.main.async { [self] in
                fans = initial
                refresh()
            }
        }
        #endif
    }

    // MARK: - Monitoring, only while the tab is on screen

    func startMonitoring() {
        isVisible = true
        refresh()
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stopMonitoring() {
        isVisible = false
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func refresh() {
        #if !DEMO
        let wantsTemperatures = isVisible
        queue.async { [self] in
            guard let smc else {
                DispatchQueue.main.async { self.availability = .noFans }
                return
            }
            let hardware = fanHardware(smc)
            let status = canControl ? FanHelper.request("status") : nil
            let temperatures = wantsTemperatures ? readTemperatures(smc) : nil
            DispatchQueue.main.async { [self] in
                apply(hardware)
                apply(status)
                if let temperatures { readings = temperatures }
                if fans.isEmpty || MacModel.current?.hasFans == false {
                    availability = .noFans
                } else if !canControl {
                    availability = .unsupported
                } else {
                    switch status?.version {
                    case nil: availability = .needsHelper
                    case FanHelper.version: availability = .ready
                    default: availability = .helperOutdated
                    }
                }
            }
        }
        #endif
    }

    private func fanHardware(_ smc: SMC) -> [(rpm: Double, minimum: Double, maximum: Double, target: Double)] {
        (0..<FanSupport.fanCount(smc)).map { fan in
            (
                Double(smc.float("F\(fan)Ac") ?? 0),
                Double(smc.float("F\(fan)Mn") ?? 0),
                Double(smc.float("F\(fan)Mx") ?? 1),
                Double(smc.float("F\(fan)Tg") ?? 0)
            )
        }
    }

    private func readTemperatures(_ smc: SMC) -> [Reading] {
        if temperatureKeys == nil {
            let all = smc.keys(prefix: "T")
            temperatureKeys = Thermals.groups(for: .current).map { group in
                (group.name, all.filter { $0.hasPrefix(group.prefix) })
            }
        }
        return (temperatureKeys ?? []).compactMap { group in
            Thermals.average(smc, keys: group.keys).map { Reading(name: group.name, celsius: Int($0.rounded())) }
        }
    }

    private func apply(_ hardware: [(rpm: Double, minimum: Double, maximum: Double, target: Double)]) {
        for (index, values) in hardware.enumerated() where index < fans.count {
            fans[index].rpm = values.rpm
            fans[index].minimum = values.minimum
            fans[index].maximum = values.maximum
            if !fans[index].isManual { fans[index].automaticTarget = values.target }
        }
    }

    private func apply(_ status: FanHelper.Status?) {
        guard let status else {
            // The helper is gone, and it put the fans back on automatic as it stopped.
            if isManual { handleRevert(reason: "helper stopped") }
            return
        }
        let wasManual = isManual
        isEngaging = status.isEngaging
        for index in fans.indices where index < status.manual.count {
            fans[index].isManual = status.manual[index]
            if status.manual[index] {
                // A slider being dragged keeps its own value until the helper catches up.
                if pendingSet[index] == nil { fans[index].target = status.target[index] }
                fans[index].floor = status.floor[index]
            }
        }
        if wasManual && !isManual && status.reason != "none" {
            handleRevert(reason: status.reason)
        }
        updateKeepAlive()
    }

    private func handleRevert(reason: String) {
        for index in fans.indices { fans[index].isManual = false }
        isEngaging = false
        fallbackReason = reason
        updateKeepAlive()
        onReverted?()
    }

    // MARK: - Control

    func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        fallbackReason = nil
        pendingSet.values.forEach { $0.cancel() }
        pendingSet.removeAll()
        switch newMode {
        case .automatic:
            for index in fans.indices { fans[index].isManual = false }
            send("auto")
        case .manual:
            // From Max this drops back to the floor, the same place Manual starts from Automatic.
            for fan in fans {
                send("set \(fan.id) \(Int(fan.isManual ? fan.floor : fan.automaticTarget))")
            }
        case .max:
            for fan in fans {
                send("set \(fan.id) \(Int(fan.maximum))")
            }
        }
    }

    func setSpeed(fan: Int, rpm: Double) {
        guard fans.indices.contains(fan) else { return }
        let rounded = (rpm / 50).rounded() * 50
        fans[fan].target = rounded
        pendingSet[fan]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingSet[fan] = nil
            self?.send("set \(fan) \(Int(rounded))")
        }
        pendingSet[fan] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    /// Used while quitting, when there's no time to wait for the helper's lease to run out.
    func restoreAutomaticNow() {
        guard isManual else { return }
        queue.sync { _ = FanHelper.request("auto") }
    }

    private func send(_ command: String) {
        queue.async { [self] in
            let status = FanHelper.request(command)
            let hardware = smc.map(fanHardware)
            DispatchQueue.main.async { [self] in
                if let hardware { apply(hardware) }
                if let status {
                    apply(status)
                } else if command.hasPrefix("set") {
                    // The helper refused: too hot, or the hardware said no.
                    fallbackReason = "refused"
                }
            }
        }
    }

    /// The helper reverts to automatic if this stops, which is what protects against a crash.
    private func updateKeepAlive() {
        if isManual, keepAliveTimer == nil {
            let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.queue.async {
                    let status = FanHelper.request("ping")
                    let hardware = self.smc.map(self.fanHardware)
                    DispatchQueue.main.async {
                        if let hardware { self.apply(hardware) }
                        self.apply(status)
                    }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            keepAliveTimer = timer
        } else if !isManual, let timer = keepAliveTimer {
            timer.invalidate()
            keepAliveTimer = nil
        }
    }

    // MARK: - Helper setup

    func installHelper() { runHelperScript("install-helper") }
    func removeHelper() { runHelperScript("uninstall-helper") }

    /// Runs a bundled script as root. macOS shows its own password prompt.
    private func runHelperScript(_ name: String) {
        guard let script = Bundle.main.path(forResource: name, ofType: "sh") else {
            helperError = "Run this from the built app."
            return
        }
        isChangingHelper = true
        helperError = nil
        let escaped = script.replacingOccurrences(of: "'", with: "'\\''")
        let source = "do shell script \"/bin/sh '\(escaped)'\" with administrator privileges"
        Task { @MainActor in
            let output = await Script.run(source)
            isChangingHelper = false
            // AppleScript's -128 means you cancelled the prompt, which isn't an error.
            if !output.succeeded, !output.cancelled {
                helperError = "That didn't work. Try again."
            }
            try? await Task.sleep(for: .milliseconds(500))
            refresh()
        }
    }
}

#if DEMO
extension FanModel {
    func loadDemo(mode demoMode: Mode = .manual, fanless: Bool = false, experimental: Bool = false, needsHelper: Bool = false) {
        let speeds: [Double]
        switch demoMode {
        case .automatic: speeds = [2500, 2700]
        case .manual: speeds = [3800, 3800]
        case .max: speeds = [5779, 6241]
        }
        let isManual = demoMode != .automatic
        fans = fanless ? [] : [
            Fan(id: 0, name: "Left fan", rpm: speeds[0], minimum: 1200, maximum: 5779, automaticTarget: 2500,
                isManual: isManual, target: speeds[0], floor: 2500),
            Fan(id: 1, name: "Right fan", rpm: speeds[1], minimum: 1200, maximum: 6241, automaticTarget: 2700,
                isManual: isManual, target: speeds[1], floor: 2700),
        ]
        readings = [("CPU", 64), ("GPU", 58), ("SSD", 41), ("Battery", 33)]
            .map { Reading(name: $0.0, celsius: $0.1) }
        isExperimental = experimental
        availability = fanless ? .noFans : (needsHelper ? .needsHelper : .ready)
    }
}
#endif
