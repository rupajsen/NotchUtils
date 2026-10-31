// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Rupaj Sen

// Exercises FanController against simulated Macs, modelled on published reverse-engineering notes
// about each chip. This checks our logic, not real hardware. Run it with scripts/check-fans.sh.

import Foundation
import SMCKit

final class FakeSMC: SMCAccess {
    enum Kind { case direct, unlock, lowercase, alwaysRefuses }

    var values: [String: [UInt8]] = [:]
    let kind: Kind
    var clock: () -> Date
    private var unlockedAt: Date?
    var writes: [String] = []

    init(kind: Kind, fans: Int, clock: @escaping () -> Date) {
        self.kind = kind
        self.clock = clock
        values["FNum"] = [UInt8(fans)]
        for fan in 0..<fans {
            setFloat("F\(fan)Mn", 1200)
            setFloat("F\(fan)Mx", 6000)
            setFloat("F\(fan)Tg", 2400)
            setFloat("F\(fan)Ac", 2400)
            values["F\(fan)\(kind == .lowercase ? "md" : "Md")"] = [kind == .unlock ? 3 : 0]
        }
        if kind == .unlock { values["Ftst"] = [0] }
    }

    func setFloat(_ key: String, _ value: Float) {
        values[key] = withUnsafeBytes(of: value) { Array($0) }
    }

    func exists(_ key: String) -> Bool { values[key] != nil }
    func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        guard let bytes = values[key] else { return nil }
        return (bytes.count == 4 ? "flt " : "ui8 ", bytes)
    }
    func keys(prefix: String) -> [String] { values.keys.filter { $0.hasPrefix(prefix) } }

    func write(_ key: String, _ bytes: [UInt8]) -> Bool {
        guard values[key] != nil else { return false }
        writes.append(key)
        let isMode = key.hasSuffix("Md") || key.hasSuffix("md")
        if kind == .alwaysRefuses, isMode, bytes == [1] { return false }
        if kind == .unlock {
            if key == "Ftst" {
                unlockedAt = bytes == [1] ? clock() : nil
                if bytes == [0] {
                    // Clearing the flag returns the fans to macOS's system mode.
                    for mode in values.keys where mode.hasSuffix("Md") { values[mode] = [3] }
                }
            } else if isMode, bytes == [1] {
                // Rejected with 0x82 until the flag has been set for a few seconds.
                guard let unlockedAt, clock().timeIntervalSince(unlockedAt) >= 3.5 else { return false }
            }
        }
        values[key] = bytes
        return true
    }

    /// What sleep reportedly does on chips with the flag.
    func simulateSleep() {
        values["Ftst"] = [0]
        for mode in values.keys where mode.hasSuffix("Md") { values[mode] = [3] }
    }
}

var failures = 0
func check(_ condition: Bool, _ name: String) {
    print("\(condition ? "ok  " : "FAIL") \(name)")
    if !condition { failures += 1 }
}

func field(_ reply: String, _ name: String) -> String {
    reply.split(whereSeparator: { $0 == " " || $0 == "\n" })
        .first { $0.hasPrefix("\(name)=") }
        .map { String($0.dropFirst(name.count + 1)) } ?? ""
}

var time = Date(timeIntervalSince1970: 1_000_000)
var hot = false
func make(_ kind: FakeSMC.Kind, fans: Int) -> (FakeSMC, FanController) {
    hot = false
    let smc = FakeSMC(kind: kind, fans: fans) { time }
    return (smc, FanController(smc: smc, now: { time }, isHot: { hot }))
}
func advance(_ controller: FanController, by seconds: Double) {
    for _ in 0..<Int(seconds * 10) {
        time.addTimeInterval(0.1)
        controller.engageTick()
        if Int(time.timeIntervalSince1970 * 10) % 10 == 0 { controller.tick() }
    }
}

print("--- M1/M2: direct writes, two fans")
do {
    let (smc, controller) = make(.direct, fans: 2)
    var reply = controller.handle("set 0 3500")
    check(field(reply, "engaging") == "0" && smc.byte("F0Md") == 1, "engages immediately")
    check(smc.float("F0Tg") == 3500, "writes the target")
    reply = controller.handle("set 0 100")
    check(smc.float("F0Tg") == 2400, "clamps to the automatic speed")
    reply = controller.handle("set 0 99999")
    check(smc.float("F0Tg") == 6000, "clamps to the maximum")
    check(controller.handle("set 5 3000") == "err\n", "rejects a fan that doesn't exist")
    check(controller.handle("set 0 nan") == "err\n", "rejects nan")
    check(controller.handle("set 0 inf") == "err\n", "rejects infinity")
    check(controller.handle("nonsense") == "err\n", "rejects unknown commands")
    check(!smc.writes.contains("Ftst"), "never touches a flag it doesn't have")
    check(field(controller.handle("status"), "version") == String(FanHelper.version), "reports its version")
    advance(controller, by: 11)
    reply = controller.handle("status")
    check(field(reply, "reason") == "lease" && smc.byte("F0Md") == 0, "lease expiry restores automatic")
}

print("--- Pings keep manual alive; heat ends it")
do {
    let (smc, controller) = make(.direct, fans: 2)
    _ = controller.handle("set 0 3500")
    for _ in 0..<6 {
        advance(controller, by: 3)
        _ = controller.handle("ping")
    }
    check(smc.byte("F0Md") == 1, "stays manual past the lease with pings")
    hot = true
    advance(controller, by: 1.1)
    check(field(controller.handle("status"), "reason") == "hot" && smc.byte("F0Md") == 0, "heat restores automatic")
    check(controller.handle("set 0 3500") == "err\n", "refuses while hot")
    hot = false
    check(controller.handle("set 0 3500") != "err\n", "allows again once cool")
}

print("--- Waking from sleep")
do {
    let (smc, controller) = make(.direct, fans: 2)
    _ = controller.handle("set 0 3500")
    // A minute passes with no ticks, as if asleep, and the app's check-in arrives first.
    time.addTimeInterval(60)
    let reply = controller.handle("ping")
    check(field(reply, "reason") == "lease" && smc.byte("F0Md") == 0, "a late check-in doesn't revive an expired lease")
}

print("--- M3/M4: unlock flag")
do {
    let (smc, controller) = make(.unlock, fans: 2)
    var reply = controller.handle("set 0 3500")
    check(field(reply, "engaging") == "1", "waits instead of failing when macOS holds the fans")
    check(smc.byte("Ftst") == 1, "sets the unlock flag")
    check(smc.byte("F0Md") == 3, "doesn't change mode yet")
    reply = controller.handle("set 1 3500")
    for _ in 0..<5 {
        advance(controller, by: 1)
        _ = controller.handle("ping")
    }
    reply = controller.handle("status")
    check(field(reply, "engaging") == "0" && smc.byte("F0Md") == 1 && smc.byte("F1Md") == 1, "engages once macOS gives way")
    check(smc.float("F0Tg") == 3500, "writes the target after engaging")
    check(smc.byte("Ftst") == 1, "keeps the flag set while manual")
    _ = controller.handle("auto")
    check(smc.byte("Ftst") == 0, "clears the flag on automatic")
    check(smc.writes.lastIndex(of: "Ftst")! > smc.writes.lastIndex(of: "F0Md")!, "clears the flag after the modes")
    check(smc.byte("F0Md") == 3, "macOS has the fans back")
}

print("--- M3/M4: sleep clears the flag")
do {
    let (smc, controller) = make(.unlock, fans: 1)
    _ = controller.handle("set 0 3500")
    for _ in 0..<5 {
        advance(controller, by: 1)
        _ = controller.handle("ping")
    }
    check(smc.byte("F0Md") == 1, "single fan engages")
    for _ in 0..<2 {
        advance(controller, by: 2)
        _ = controller.handle("ping")
    }
    smc.simulateSleep()
    advance(controller, by: 1.1)
    let reply = controller.handle("status")
    check(field(reply, "reason") == "system" && field(reply, "manual") == "0", "reports losing control instead of pretending")
}

print("--- M3/M4: macOS never gives way")
do {
    let (smc, _) = make(.alwaysRefuses, fans: 2)
    smc.values["Ftst"] = [0]
    let controllerWithFlag = FanController(smc: smc, now: { time }, isHot: { false })
    _ = controllerWithFlag.handle("set 0 3500")
    for _ in 0..<11 {
        advance(controllerWithFlag, by: 1)
        _ = controllerWithFlag.handle("ping")
    }
    let reply = controllerWithFlag.handle("status")
    check(field(reply, "reason") == "refused" && field(reply, "manual") == "0,0", "gives up after the timeout")
    check(smc.byte("Ftst") == 0, "clears the flag after giving up")
}

print("--- M5: lowercase key, no flag")
do {
    let (smc, controller) = make(.lowercase, fans: 2)
    let reply = controller.handle("set 0 3500")
    check(field(reply, "engaging") == "0" && smc.byte("F0md") == 1, "engages through the lowercase key")
    check(smc.float("F0Tg") == 3500, "writes the target")
    check(!smc.writes.contains("Ftst"), "never touches a flag it doesn't have")
    _ = controller.handle("auto")
    check(smc.byte("F0md") == 0, "restores through the lowercase key")
}

print("--- A Mac with no unlock that refuses")
do {
    let (smc, controller) = make(.alwaysRefuses, fans: 1)
    check(controller.handle("set 0 3500") == "err\n", "reports failure straight away")
    check(smc.byte("F0Md") == 0, "stays automatic")
}

print("--- Model table")
do {
    check(MacModel.lookup("MacBookPro18,3")?.chip == .m1 && MacModel.lookup("MacBookPro18,3")?.hasFans == true, "14-inch M1 Pro has fans")
    check(MacModel.lookup("Mac16,6")?.hasFans == true, "14-inch M4 Pro has fans")
    check(MacModel.lookup("Mac17,7")?.chip == .m5, "14-inch M5 Pro is M5")
    check(MacModel.lookup("Mac14,2")?.hasFans == false, "MacBook Air M2 has no fans")
    check(MacModel.lookup("Mac17,4")?.hasFans == false, "MacBook Air M5 has no fans")
    check(MacModel.lookup("Mac14,7") == nil, "13-inch M2 MacBook Pro has no notch, so isn't listed")
    check(MacModel.lookup("MacBookAir10,1") == nil, "M1 MacBook Air has no notch, so isn't listed")
    check(MacModel.lookup("MacBookPro18,3")?.isFanControlExperimental == false, "M1 Pro isn't experimental")
    check(MacModel.lookup("Mac14,9")?.isFanControlExperimental == true, "M2 Pro is experimental")
    check(MacModel.lookup("Mac17,7")?.isFanControlExperimental == true, "M5 Pro is experimental")
    check(Thermals.groups(for: nil).isEmpty, "an unknown Mac shows no temperature labels")
    check(!Thermals.groups(for: MacModel.lookup("MacBookPro18,3")).contains { $0.name == "Memory" }, "unconfirmed rings are gone")
    check(Thermals.groups(for: MacModel.lookup("Mac16,6")).map(\.name) == ["SSD", "Battery"], "M4 shows only the rings not tied to chip layout")
}

print(failures == 0 ? "All checks passed" : "\(failures) checks FAILED")
exit(failures == 0 ? 0 : 1)
