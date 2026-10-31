// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Rupaj Sen

import Foundation

/// The rules for taking and giving back manual fan control. The root helper runs this; it's separate
/// from the helper so scripts/check-fans.sh can exercise every chip generation against a simulated SMC.
///
/// How the chips differ, none of it documented by Apple:
///   - M1, M2: `F0Md` is writable directly.
///   - M3, M4: macOS holds the fans in a system mode and rejects `F0Md` until the `Ftst` flag is set,
///     then gives way after a few seconds. `Ftst` has to stay set while manual, and sleep clears it.
///   - M5: the mode key is lowercase, `F0md`, and there's no `Ftst`.
public final class FanController {
    static let leaseSeconds: TimeInterval = 10
    static let engageTimeout: TimeInterval = 10
    /// The mode can read stale for a moment after a successful write.
    static let settleSeconds: TimeInterval = 3

    private struct FanState {
        var isManual = false
        var isEngaged = false
        var floor = 0.0
        var target = 0.0
        var deadline = Date.distantPast
        var engagedAt = Date.distantPast
    }

    private let smc: SMCAccess
    private let now: () -> Date
    private let isHot: () -> Bool
    private let log: (String) -> Void
    private let fanCount: Int
    private let modeKeyFormat: String
    private let hasUnlockFlag: Bool

    private var fans: [FanState]
    private var leaseExpiry = Date.distantPast
    private var reason = "none"

    public init(
        smc: SMCAccess,
        now: @escaping () -> Date = Date.init,
        isHot: @escaping () -> Bool,
        log: @escaping (String) -> Void = { _ in }
    ) {
        self.smc = smc
        self.now = now
        self.isHot = isHot
        self.log = log
        fanCount = FanSupport.fanCount(smc)
        modeKeyFormat = FanSupport.modeKey(smc, fan: 0).hasSuffix("md") ? "md" : "Md"
        hasUnlockFlag = smc.exists("Ftst")
        fans = [FanState](repeating: FanState(), count: fanCount)
    }

    private func modeKey(_ fan: Int) -> String { "F\(fan)\(modeKeyFormat)" }

    /// True while a fan is waiting for macOS to give way, which needs checking more than once a second.
    public var isEngaging: Bool {
        fans.contains { $0.isManual && !$0.isEngaged }
    }

    /// Called at startup too, since a previous run may have been killed while manual.
    public func restoreAutomatic(because why: String?) {
        let wasManual = fans.contains(where: \.isManual)
        for fan in 0..<fanCount {
            _ = smc.write(modeKey(fan), [0])
            fans[fan] = FanState()
        }
        // Clearing this last is what hands the fans back to macOS on chips that have it.
        if hasUnlockFlag { _ = smc.write("Ftst", [0]) }
        if let why, wasManual {
            reason = why
            log("returned to automatic: \(why)")
        }
    }

    public func handle(_ line: String) -> String {
        let words = line.split(separator: " ")
        switch words.first {
        case "status":
            return statusLine()
        case "ping":
            if fans.contains(where: \.isManual) { leaseExpiry = now().addingTimeInterval(Self.leaseSeconds) }
            return statusLine()
        case "auto":
            restoreAutomatic(because: nil)
            reason = "none"
            return statusLine()
        case "set":
            guard words.count == 3, let fan = Int(words[1]), let rpm = Double(words[2]) else { return "err\n" }
            return setSpeed(fan: fan, rpm: rpm) ? statusLine() : "err\n"
        default:
            return "err\n"
        }
    }

    /// Run about once a second while the helper is up.
    public func tick() {
        guard fans.contains(where: \.isManual) else { return }
        if now() > leaseExpiry {
            restoreAutomatic(because: "lease")
        } else if isHot() {
            restoreAutomatic(because: "hot")
        } else if lostControl() {
            // Sleep clears the unlock flag, and macOS can take the fans back under heavy load.
            restoreAutomatic(because: "system")
        }
    }

    /// Run about ten times a second while `isEngaging`.
    public func engageTick() {
        for fan in fans.indices where fans[fan].isManual && !fans[fan].isEngaged {
            if now() > fans[fan].deadline {
                restoreAutomatic(because: "refused")
                return
            }
            tryEngage(fan)
        }
    }

    private func lostControl() -> Bool {
        fans.indices.contains { fan in
            fans[fan].isEngaged
                && now().timeIntervalSince(fans[fan].engagedAt) > Self.settleSeconds
                && smc.byte(modeKey(fan)) != 1
        }
    }

    private func setSpeed(fan: Int, rpm: Double) -> Bool {
        guard fan >= 0, fan < fanCount, rpm.isFinite, !isHot(),
              let minimum = smc.float("F\(fan)Mn"), let maximum = smc.float("F\(fan)Mx") else { return false }

        if !fans[fan].isManual {
            // Capture what macOS wants right now before taking over, because that's the floor.
            let automatic = smc.float("F\(fan)Tg") ?? smc.float("F\(fan)Ac") ?? maximum
            fans[fan].floor = Double(max(automatic, minimum))
            fans[fan].isManual = true
            fans[fan].deadline = now().addingTimeInterval(Self.engageTimeout)
        }
        fans[fan].target = min(max(rpm, fans[fan].floor), Double(maximum))
        leaseExpiry = now().addingTimeInterval(Self.leaseSeconds)
        reason = "none"

        if fans[fan].isEngaged {
            if smc.write("F\(fan)Tg", float: Float(fans[fan].target)) { return true }
            restoreAutomatic(because: "write failed")
            return false
        }
        tryEngage(fan)
        // On Macs with no unlock to wait for, a refused write is final.
        if !fans[fan].isEngaged, !hasUnlockFlag {
            restoreAutomatic(because: nil)
            return false
        }
        return fans[fan].isManual
    }

    private func tryEngage(_ fan: Int) {
        guard smc.write(modeKey(fan), [1]) else {
            if hasUnlockFlag, smc.byte("Ftst") != 1 { _ = smc.write("Ftst", [1]) }
            return
        }
        guard smc.write("F\(fan)Tg", float: Float(fans[fan].target)) else {
            restoreAutomatic(because: "write failed")
            return
        }
        fans[fan].isEngaged = true
        fans[fan].engagedAt = now()
    }

    private func statusLine() -> String {
        let manual = fans.map { $0.isManual ? "1" : "0" }.joined(separator: ",")
        let target = fans.map { String(Int($0.target)) }.joined(separator: ",")
        let floor = fans.map { String(Int($0.floor)) }.joined(separator: ",")
        let engaging = isEngaging ? "1" : "0"
        return "ok manual=\(manual) target=\(target) floor=\(floor) engaging=\(engaging) reason=\(reason) version=\(FanHelper.version)\n"
    }
}
