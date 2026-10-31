// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Rupaj Sen

import Darwin

/// Macs with a notch, from Apple's "Identify your MacBook Pro/Air model" pages
/// (support.apple.com/108052 and /102869). Add new models here as Apple releases them.
public struct MacModel: Equatable {
    public enum Chip: Int, Comparable {
        case m1, m2, m3, m4, m5

        public static func < (lhs: Chip, rhs: Chip) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let chip: Chip
    /// False for every MacBook Air. How many fans a MacBook Pro has comes from the Mac itself,
    /// because the base 14-inch M3, M4 and M5 have one and the rest have two.
    public let hasFans: Bool

    /// Fan control has only been tried on M1 Pro hardware. The app says so on everything else
    /// until owners confirm it.
    public var isFanControlExperimental: Bool { chip != .m1 }

    private static let table: [String: MacModel] = {
        var models: [String: MacModel] = [:]
        func add(_ chip: Chip, hasFans: Bool, _ identifiers: String...) {
            for identifier in identifiers {
                models[identifier] = MacModel(chip: chip, hasFans: hasFans)
            }
        }
        // MacBook Pro, 14-inch and 16-inch.
        add(.m1, hasFans: true, "MacBookPro18,1", "MacBookPro18,2", "MacBookPro18,3", "MacBookPro18,4")
        add(.m2, hasFans: true, "Mac14,5", "Mac14,6", "Mac14,9", "Mac14,10")
        add(.m3, hasFans: true, "Mac15,3", "Mac15,6", "Mac15,7", "Mac15,8", "Mac15,9", "Mac15,10", "Mac15,11")
        add(.m4, hasFans: true, "Mac16,1", "Mac16,5", "Mac16,6", "Mac16,7", "Mac16,8")
        add(.m5, hasFans: true, "Mac17,2", "Mac17,6", "Mac17,7", "Mac17,8", "Mac17,9")
        // MacBook Air.
        add(.m2, hasFans: false, "Mac14,2", "Mac14,15")
        add(.m3, hasFans: false, "Mac15,12", "Mac15,13")
        add(.m4, hasFans: false, "Mac16,12", "Mac16,13")
        add(.m5, hasFans: false, "Mac17,3", "Mac17,4")
        return models
    }()

    public static func lookup(_ identifier: String) -> MacModel? {
        table[identifier]
    }

    /// Nil for anything not listed, such as a Mac newer than this build.
    public static let current: MacModel? = lookup(currentIdentifier)

    public static var currentIdentifier: String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }
}
