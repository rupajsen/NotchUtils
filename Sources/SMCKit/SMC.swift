// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Rupaj Sen

import Foundation
import IOKit

public protocol SMCAccess: AnyObject {
    func exists(_ key: String) -> Bool
    func read(_ key: String) -> (type: String, bytes: [UInt8])?
    func write(_ key: String, _ bytes: [UInt8]) -> Bool
    func keys(prefix: String) -> [String]
}

extension SMCAccess {
    public func float(_ key: String) -> Float? {
        guard let value = read(key), value.type.hasPrefix("flt"), value.bytes.count == 4 else { return nil }
        return value.bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
    }

    public func byte(_ key: String) -> UInt8? {
        guard let value = read(key), value.bytes.count == 1 else { return nil }
        return value.bytes[0]
    }

    public func write(_ key: String, float value: Float) -> Bool {
        write(key, withUnsafeBytes(of: value) { Array($0) })
    }
}

/// A connection to the Mac's System Management Controller. Anyone can read; writing needs root.
public final class SMC: SMCAccess {
    private struct Version {
        var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct PowerLimit {
        var version: UInt16 = 0, length: UInt16 = 0
        var cpu: UInt32 = 0, gpu: UInt32 = 0, memory: UInt32 = 0
    }

    // The padding is explicit because Swift would otherwise pack the next field into it,
    // and the kernel expects this struct's 80-byte C layout.
    private struct KeyInfo {
        var size: UInt32 = 0, type: UInt32 = 0
        var attributes: UInt8 = 0, pad0: UInt8 = 0, pad1: UInt8 = 0, pad2: UInt8 = 0
    }

    private struct Message {
        typealias Bytes = (
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
        )

        var key: UInt32 = 0
        var version = Version()
        var limit = PowerLimit()
        var info = KeyInfo()
        var result: UInt8 = 0, status: UInt8 = 0, command: UInt8 = 0
        var index: UInt32 = 0
        var bytes: Bytes = (
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    private enum Command {
        static let read: UInt8 = 5
        static let write: UInt8 = 6
        static let keyAtIndex: UInt8 = 8
        static let keyInfo: UInt8 = 9
    }

    private var connection: io_connect_t = 0

    public init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
    }

    deinit {
        IOServiceClose(connection)
    }

    private func call(_ message: inout Message) -> Bool {
        var output = Message()
        var size = MemoryLayout<Message>.stride
        let result = IOConnectCallStructMethod(
            connection, 2, &message, MemoryLayout<Message>.stride, &output, &size
        )
        message = output
        return result == KERN_SUCCESS && output.result == 0
    }

    private func info(for key: String) -> KeyInfo? {
        var message = Message()
        message.key = Self.code(key)
        message.command = Command.keyInfo
        return call(&message) ? message.info : nil
    }

    public func exists(_ key: String) -> Bool {
        info(for: key) != nil
    }

    public func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        guard let info = info(for: key) else { return nil }
        var message = Message()
        message.key = Self.code(key)
        message.info = info
        message.command = Command.read
        guard call(&message) else { return nil }
        let bytes = withUnsafeBytes(of: message.bytes) { Array($0.prefix(Int(info.size))) }
        return (Self.name(info.type), bytes)
    }

    public func write(_ key: String, _ bytes: [UInt8]) -> Bool {
        guard let info = info(for: key), Int(info.size) == bytes.count else { return false }
        var message = Message()
        message.key = Self.code(key)
        message.info = info
        message.command = Command.write
        withUnsafeMutableBytes(of: &message.bytes) { buffer in
            for (index, byte) in bytes.enumerated() { buffer[index] = byte }
        }
        return call(&message)
    }

    public func keys(prefix: String) -> [String] {
        guard let total = read("#KEY")?.bytes.reduce(UInt32(0), { $0 << 8 | UInt32($1) }) else { return [] }
        return (0..<total).compactMap { index in
            var message = Message()
            message.command = Command.keyAtIndex
            message.index = index
            guard call(&message) else { return nil }
            let key = Self.name(message.key)
            return key.hasPrefix(prefix) ? key : nil
        }
    }

    private static func code(_ key: String) -> UInt32 {
        key.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func name(_ code: UInt32) -> String {
        String(decoding: [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xFF) }, as: UTF8.self)
    }
}

public enum Thermals {
    /// What each ring on the Thermals tab averages. Apple doesn't document these sensors and their
    /// names change between chips, so each chip only gets the groups known to mean that on it.
    /// `Te` and `Tm` are left out everywhere: under load they moved with everything else, so
    /// there's no evidence they measure efficiency cores and memory.
    public static func groups(for model: MacModel?) -> [(name: String, prefix: String)] {
        let storage = [("SSD", "TH0"), ("Battery", "TB")]
        switch model?.chip {
        case .m1, .m2:
            return [("CPU", "Tp"), ("GPU", "Tg")] + storage
        case .m3, .m4, .m5:
            return storage
        case nil:
            return []
        }
    }

    public static func average(_ smc: SMCAccess, keys: [String]) -> Double? {
        // Filters out the unused sensors that report nonsense values.
        let values = keys.compactMap { smc.float($0) }.filter { $0 > 5 && $0 < 130 }
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }
}

public enum FanSupport {
    public static func fanCount(_ smc: SMCAccess) -> Int {
        Int(smc.byte("FNum") ?? 0)
    }

    /// M5 renamed the mode key from `F0Md` to `F0md`.
    public static func modeKey(_ smc: SMCAccess, fan: Int) -> String {
        smc.exists("F\(fan)md") ? "F\(fan)md" : "F\(fan)Md"
    }

    /// Requires a listed MacBook with a notch and fans, as well as the keys this code knows how to use.
    public static func canControl(_ smc: SMCAccess, model: MacModel? = .current) -> Bool {
        guard model?.hasFans == true else { return false }
        let count = fanCount(smc)
        guard count > 0 else { return false }
        return (0..<count).allSatisfy { fan in
            smc.exists(modeKey(smc, fan: fan)) && ["Ac", "Mn", "Mx", "Tg"].allSatisfy { smc.exists("F\(fan)\($0)") }
        }
    }
}

/// The small line-based protocol between the app and the root helper.
public enum FanHelper {
    public static let label = "io.github.rupajsen.notchutils.fanhelper"
    public static let socketPath = "/var/run/\(label).sock"
    /// Bump when the helper's behaviour changes, so an updated app asks to replace the installed one.
    /// Helpers from before this existed don't report it, and count as version 1.
    public static let version = 4

    public struct Status {
        public var manual: [Bool]
        public var target: [Double]
        public var floor: [Double]
        public var isEngaging: Bool
        public var reason: String
        public var version: Int
    }

    /// Sends one command and waits for the reply. Blocks for up to a second, so call off the main thread.
    public static func request(_ command: String) -> Status? {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSignal: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))

        var address = socketAddress()
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }

        let line = Array((command + "\n").utf8)
        guard send(descriptor, line, line.count, 0) == line.count else { return nil }
        var buffer = [UInt8](repeating: 0, count: 512)
        let count = recv(descriptor, &buffer, buffer.count, 0)
        guard count > 0 else { return nil }
        return parse(String(decoding: buffer.prefix(count), as: UTF8.self))
    }

    public static func socketAddress() -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (index, byte) in socketPath.utf8.prefix(buffer.count - 1).enumerated() {
                buffer[index] = byte
            }
        }
        return address
    }

    private static func parse(_ reply: String) -> Status? {
        let words = reply.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        guard words.first == "ok" else { return nil }
        var fields: [String: String] = [:]
        for word in words.dropFirst() {
            let parts = word.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { fields[String(parts[0])] = String(parts[1]) }
        }
        let numbers: (String) -> [Double] = { key in
            (fields[key] ?? "").split(separator: ",").compactMap { Double($0) }
        }
        return Status(
            manual: numbers("manual").map { $0 != 0 },
            target: numbers("target"),
            floor: numbers("floor"),
            isEngaging: fields["engaging"] == "1",
            reason: fields["reason"] ?? "none",
            version: fields["version"].flatMap { Int($0) } ?? 1
        )
    }
}
