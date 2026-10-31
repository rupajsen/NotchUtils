// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Rupaj Sen

import AppKit
import AudioToolbox
import CoreAudio
import IOKit.ps
import IOKit.pwr_mgt
import ServiceManagement

final class SystemModel: ObservableObject {
    @Published private(set) var batteryLevel = 1.0
    @Published private(set) var isCharging = false
    @Published private(set) var isOnPower = false
    @Published private(set) var minutesToEmpty: Int?
    @Published private(set) var cpu = 0.0
    @Published private(set) var memory = 0.0
    @Published private(set) var storage = 0.0
    @Published private(set) var volume: Double?
    @Published private(set) var keepAwake = false
    @Published private(set) var opensAtLogin = SMAppService.mainApp.status == .enabled

    var onPluggedIn: (() -> Void)?

    private var sampler: Timer?
    private var lastTicks: (busy: UInt64, total: UInt64)?
    private var assertion: IOPMAssertionID = 0

    init() {
        readBattery()
        readCPU()
        let context = Unmanaged.passUnretained(self).toOpaque()
        let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<SystemModel>.fromOpaque(context).takeUnretainedValue().powerSourceChanged()
        }, context).takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    var batterySymbol: String {
        if isCharging || isOnPower { return "battery.100percent.bolt" }
        switch batteryLevel {
        case ..<0.13: return "battery.0percent"
        case ..<0.38: return "battery.25percent"
        case ..<0.63: return "battery.50percent"
        case ..<0.88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    // MARK: - Sampling, only while the System tab is on screen

    func startSampling() {
        #if DEMO
        return
        #endif
        sample()
        guard sampler == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(timer, forMode: .common)
        sampler = timer
    }

    func stopSampling() {
        sampler?.invalidate()
        sampler = nil
    }

    private func sample() {
        readCPU()
        readMemory()
        readStorage()
        readVolume()
    }

    private func powerSourceChanged() {
        #if DEMO
        return
        #endif
        let wasOnPower = isOnPower
        readBattery()
        if isOnPower && !wasOnPower { onPluggedIn?() }
    }

    private func readBattery() {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            let current = info[kIOPSCurrentCapacityKey] as? Double ?? 100
            let maximum = info[kIOPSMaxCapacityKey] as? Double ?? 100
            batteryLevel = maximum > 0 ? current / maximum : 1
            isCharging = info[kIOPSIsChargingKey] as? Bool ?? false
            isOnPower = info[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let minutes = info[kIOPSTimeToEmptyKey] as? Int ?? -1
            minutesToEmpty = minutes > 0 && !isOnPower ? minutes : nil
            return
        }
    }

    private func readCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let (user, system, idle, nice) = info.cpu_ticks
        let busy = UInt64(user) + UInt64(system) + UInt64(nice)
        let total = busy + UInt64(idle)
        if let last = lastTicks, total > last.total {
            cpu = Double(busy - last.busy) / Double(total - last.total)
        }
        lastTicks = (busy, total)
    }

    private func readMemory() {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        // The same sum Activity Monitor calls "Memory Used".
        let pages = UInt64(info.internal_page_count) - UInt64(info.purgeable_count)
            + UInt64(info.wire_count) + UInt64(info.compressor_page_count)
        memory = Double(pages * UInt64(getpagesize())) / Double(ProcessInfo.processInfo.physicalMemory)
    }

    private func readStorage() {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, total > 0,
              let free = values.volumeAvailableCapacityForImportantUsage else { return }
        storage = 1 - Double(free) / Double(total)
    }

    // MARK: - Volume

    private func outputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return status == noErr ? device : nil
    }

    private var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func readVolume() {
        guard let device = outputDevice() else { volume = nil; return }
        var address = volumeAddress
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioHardwareServiceGetPropertyData(device, &address, 0, nil, &size, &value)
        // HDMI and some USB outputs have no software volume.
        volume = status == noErr ? Double(value) : nil
    }

    func setVolume(_ newValue: Double) {
        guard let device = outputDevice() else { return }
        var address = volumeAddress
        var value = Float32(newValue)
        let size = UInt32(MemoryLayout<Float32>.size)
        if AudioHardwareServiceSetPropertyData(device, &address, 0, nil, size, &value) == noErr {
            volume = newValue
        }
    }

    // MARK: - Actions

    func toggleKeepAwake() {
        if keepAwake {
            IOPMAssertionRelease(assertion)
            keepAwake = false
        } else {
            let status = IOPMAssertionCreateWithName(
                kIOPMAssertionTypeNoDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "NotchUtils Keep Awake" as CFString,
                &assertion
            )
            keepAwake = status == kIOReturnSuccess
        }
    }

    func toggleOpenAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("NotchUtils: open at login failed: \(error)")
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }

    func takeScreenshot() {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app"),
            configuration: .init()
        )
    }

    func sleepDisplay() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        try? process.run()
    }
}

#if DEMO
extension SystemModel {
    func loadDemo() {
        batteryLevel = 0.82
        isCharging = false
        isOnPower = false
        minutesToEmpty = 412
        cpu = 0.24
        memory = 0.58
        storage = 0.41
        volume = 0.6
    }
}
#endif
