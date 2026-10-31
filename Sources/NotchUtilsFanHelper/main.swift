// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Rupaj Sen

// The root helper that changes fan speeds. Every safety rule is enforced here or in FanController, not
// in the app, so they hold whatever a client asks for and whether or not the app is still running:
//   - Speeds stay between what macOS was asking for when manual control began and the fan's maximum.
//   - Fans return to automatic if the app stops checking in, the Mac gets hot, macOS takes the fans
//     back, or this helper exits.
//   - It accepts only four fixed commands, and only from the logged-in user.

import Foundation
import SMCKit

/// Averages for each chip group. `--temp-limit` lowers this, for testing the fallback.
var temperatureLimit = 95.0
if let index = CommandLine.arguments.firstIndex(of: "--temp-limit"), index + 1 < CommandLine.arguments.count,
   let limit = Double(CommandLine.arguments[index + 1]) {
    temperatureLimit = limit
}

func say(_ message: String) {
    print("notchutils-fanhelper: \(message)")
    fflush(stdout)
}

guard getuid() == 0 else {
    say("must run as root")
    exit(1)
}
guard let smc = SMC(), FanSupport.canControl(smc) else {
    say("fan control isn't supported on this Mac (\(MacModel.currentIdentifier))")
    exit(1)
}

// A second copy would take over the socket from the first and leave it running unreachable.
if FanHelper.request("status") != nil {
    say("already running")
    exit(1)
}

// Sensor names vary by chip, so this watches every group that could be a CPU or GPU on any of them.
let chipSensors = ["Tp", "Te", "Tf", "Tg"]
    .map { smc.keys(prefix: $0) }
    .filter { !$0.isEmpty }
guard !chipSensors.isEmpty else {
    // Without temperatures the overheating fallback couldn't work, so don't offer manual control at all.
    say("no temperature sensors found")
    exit(1)
}

func isHot() -> Bool {
    if ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
        return true
    }
    return chipSensors.contains { (Thermals.average(smc, keys: $0) ?? 0) >= temperatureLimit }
}

let controller = FanController(smc: smc, isHot: isHot, log: say)
controller.restoreAutomatic(because: nil)

/// While waiting for macOS to give way, which can take several seconds on M3 and M4.
func runEngageTicks() {
    guard controller.isEngaging else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        controller.engageTick()
        runEngageTicks()
    }
}

/// Only the person at the Mac may send commands, even though the limits would still apply.
func isAllowedClient(_ descriptor: Int32) -> Bool {
    var uid: uid_t = 0
    var gid: gid_t = 0
    guard getpeereid(descriptor, &uid, &gid) == 0 else { return false }
    var console = stat()
    guard stat("/dev/console", &console) == 0 else { return uid == 0 }
    return uid == 0 || uid == console.st_uid
}

func serve(_ listener: Int32) {
    let client = accept(listener, nil, nil)
    guard client >= 0 else { return }
    defer { close(client) }

    var timeout = timeval(tv_sec: 1, tv_usec: 0)
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var noSignal: Int32 = 1
    setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
    guard isAllowedClient(client) else { return }

    var buffer = [UInt8](repeating: 0, count: 64)
    let count = recv(client, &buffer, buffer.count, 0)
    guard count > 0 else { return }
    let line = String(decoding: buffer.prefix(count), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let wasEngaging = controller.isEngaging
    let reply = Array(controller.handle(line).utf8)
    _ = send(client, reply, reply.count, 0)
    if !wasEngaging { runEngageTicks() }
}

unlink(FanHelper.socketPath)
let listener = socket(AF_UNIX, SOCK_STREAM, 0)
var address = FanHelper.socketAddress()
let bound = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard listener >= 0, bound == 0, chmod(FanHelper.socketPath, 0o666) == 0, listen(listener, 8) == 0 else {
    say("couldn't open \(FanHelper.socketPath)")
    exit(1)
}

let accepts = DispatchSource.makeReadSource(fileDescriptor: listener, queue: .main)
accepts.setEventHandler { serve(listener) }
accepts.resume()

let watchdog = DispatchSource.makeTimerSource(queue: .main)
watchdog.schedule(deadline: .now() + 1, repeating: 1)
watchdog.setEventHandler { controller.tick() }
watchdog.resume()

var signalSources: [DispatchSourceSignal] = []
for number in [SIGTERM, SIGINT, SIGHUP] {
    signal(number, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
    source.setEventHandler {
        controller.restoreAutomatic(because: "helper stopped")
        unlink(FanHelper.socketPath)
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}

say("ready, \(MacModel.currentIdentifier), \(FanSupport.fanCount(smc)) fans, temperature limit \(Int(temperatureLimit))C")
dispatchMain()
