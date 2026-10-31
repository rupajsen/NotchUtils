// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Rupaj Sen

import AppKit
import CoreImage
import SwiftUI

enum MediaSource: String, CaseIterable {
    case spotify = "Spotify"
    case music = "Music"

    var bundleID: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .music: "com.apple.Music"
        }
    }

    var isRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { !$0.isTerminated }
    }

    var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// Returns state, title, artist, album, duration (s), position (s), artwork URL, one per line.
    fileprivate var stateScript: String {
        switch self {
        case .spotify:
            """
            tell application "Spotify"
                if player state is stopped then return "stopped"
                set t to current track
                return (player state as string) & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & ((duration of t) / 1000) & linefeed & (player position) & linefeed & (artwork url of t)
            end tell
            """
        case .music:
            """
            tell application "Music"
                if player state is stopped then return "stopped"
                set t to current track
                return (player state as string) & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & (duration of t) & linefeed & (player position) & linefeed & ""
            end tell
            """
        }
    }
}

struct Track: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var artworkURL: String?
}

/// osascript rather than NSAppleScript so a slow app or a permission prompt never blocks the UI.
enum Script {
    struct Output {
        var text: String
        var notAuthorized: Bool
        var succeeded: Bool
        var cancelled = false
    }

    static func run(_ source: String) async -> Output {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            do { try process.run() } catch {
                return Output(text: "", notAuthorized: false, succeeded: false)
            }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let errText = String(decoding: errData, as: UTF8.self)
            return Output(
                text: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
                notAuthorized: errText.contains("-1743"),
                succeeded: process.terminationStatus == 0,
                cancelled: errText.contains("-128")
            )
        }.value
    }
}

final class MediaModel: ObservableObject {
    @Published private(set) var source: MediaSource?
    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: Color = .white
    @Published private(set) var needsPermission = false

    private var anchorPosition: Double = 0
    private var anchorDate = Date()
    private var artworkKey: String?
    private var refreshID = 0
    private var observers: [NSObjectProtocol] = []

    init() {
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(
            forName: .init("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main
        ) { [weak self] note in
            // Spotify posts "Stopped" while quitting; scripting it then would relaunch it.
            if note.userInfo?["Player State"] as? String == "Stopped" {
                if self?.source == .spotify { self?.clear() }
                return
            }
            self?.refresh()
        })
        observers.append(distributed.addObserver(
            forName: .init("com.apple.Music.playerInfo"), object: nil, queue: .main
        ) { [weak self] note in
            if note.userInfo?["Player State"] as? String == "Stopped" {
                if self?.source == .music { self?.clear() }
                return
            }
            self?.refresh()
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == self?.source?.bundleID { self?.clear() }
        })
        refresh()
    }

    func position(at date: Date = Date()) -> Double {
        let elapsed = isPlaying ? date.timeIntervalSince(anchorDate) : 0
        return min(anchorPosition + elapsed, track?.duration ?? 0)
    }

    func refresh() {
        #if DEMO
        return
        #else
        refreshID += 1
        let id = refreshID
        Task { @MainActor in
            var candidates: [(MediaSource, [String])] = []
            var denied = false
            // Checking first matters: telling an app that isn't running launches it.
            for source in MediaSource.allCases where source.isRunning {
                let output = await Script.run(source.stateScript)
                denied = denied || output.notAuthorized
                let lines = output.text.components(separatedBy: "\n")
                if output.succeeded, lines.count >= 6 { candidates.append((source, lines)) }
            }
            guard id == refreshID else { return }
            needsPermission = denied
            let pick = candidates.first { $0.1[0] == "playing" } ?? candidates.first
            guard let (source, lines) = pick else {
                clear()
                return
            }
            apply(source: source, lines: lines)
        }
        #endif
    }

    private func apply(source: MediaSource, lines: [String]) {
        let number: (String) -> Double = { Double($0.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        let newTrack = Track(
            title: lines[1],
            artist: lines[2],
            album: lines[3],
            duration: number(lines[4]),
            artworkURL: lines.count > 6 && !lines[6].isEmpty ? lines[6] : nil
        )
        self.source = source
        track = newTrack
        isPlaying = lines[0] == "playing"
        anchorPosition = number(lines[5])
        anchorDate = Date()
        loadArtwork(for: newTrack, from: source)
    }

    private func clear() {
        source = nil
        track = nil
        isPlaying = false
        artwork = nil
        artworkKey = nil
        accent = .white
    }

    // MARK: - Transport

    func playPause() {
        guard let source else { return }
        anchorPosition = position()
        anchorDate = Date()
        isPlaying.toggle()
        send("playpause", to: source)
    }

    func next() {
        if let source { send("next track", to: source) }
    }

    func previous() {
        if let source { send("previous track", to: source) }
    }

    func seek(to seconds: Double) {
        guard let source else { return }
        anchorPosition = seconds
        anchorDate = Date()
        objectWillChange.send()
        send("set player position to \(seconds)", to: source)
    }

    func open(_ source: MediaSource) {
        guard let url = source.appURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    private func send(_ command: String, to source: MediaSource) {
        guard source.isRunning else { return }
        Task { @MainActor in
            _ = await Script.run("tell application \"\(source.rawValue)\" to \(command)")
            try? await Task.sleep(for: .milliseconds(250))
            refresh()
        }
    }

    // MARK: - Artwork

    private func loadArtwork(for track: Track, from source: MediaSource) {
        let key = "\(source.rawValue)|\(track.artist)|\(track.album)"
        guard key != artworkKey else { return }
        artworkKey = key
        Task { @MainActor in
            let image: NSImage?
            if let string = track.artworkURL, let url = URL(string: string) {
                let data = try? await URLSession.shared.data(from: url).0
                image = data.flatMap(NSImage.init(data:))
            } else {
                image = await Self.musicArtwork()
            }
            guard key == artworkKey else { return }
            artwork = image
            accent = image.map(Self.accentColor(of:)) ?? .white
        }
    }

    private static func musicArtwork() async -> NSImage? {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("notchutils-artwork")
        let output = await Script.run("""
        tell application "Music" to set d to raw data of artwork 1 of current track
        set f to open for access POSIX file "\(file.path)" with write permission
        set eof f to 0
        write d to f
        close access f
        """)
        guard output.succeeded, let data = try? Data(contentsOf: file) else { return nil }
        return NSImage(data: data)
    }

    /// The artwork's average colour, lifted so it stays legible on black.
    private static func accentColor(of image: NSImage) -> Color {
        guard let tiff = image.tiffRepresentation, let input = CIImage(data: tiff),
              let filter = CIFilter(name: "CIAreaAverage", parameters: [
                  kCIInputImageKey: input,
                  kCIInputExtentKey: CIVector(cgRect: input.extent),
              ]),
              let output = filter.outputImage
        else { return .white }
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext().render(
            output, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let color = NSColor(
            srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255, alpha: 1
        )
        return Color(
            hue: color.hueComponent,
            saturation: min(color.saturationComponent * 1.3, 0.75),
            brightness: max(color.brightnessComponent, 0.85)
        )
    }
}

#if DEMO
extension MediaModel {
    func loadDemo(artwork image: NSImage) {
        source = .music
        track = Track(title: "Midnight Bezel", artist: "The Placeholders", album: "Demo Data", duration: 214)
        isPlaying = true
        anchorPosition = 71
        anchorDate = Date()
        artwork = image
        accent = Color(hue: 0.9, saturation: 0.55, brightness: 1)
    }
}
#endif
