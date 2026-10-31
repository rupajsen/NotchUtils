// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Rupaj Sen

#if DEMO
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Renders the README's screenshots and demo GIF from the app's real views, filled with made-up
/// data. Only compiled by scripts/render-demo.sh; release builds contain none of this, and this
/// build never reads your music or files.
final class DemoClock: ObservableObject {
    static let shared = DemoClock()
    @Published var time: Double = 0
}

struct DemoBars: View {
    let color: Color
    @ObservedObject private var clock = DemoClock.shared

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<4, id: \.self) { index in
                let wave = sin(clock.time * (5.5 + Double(index) * 1.7) + Double(index))
                Capsule()
                    .fill(color)
                    .frame(width: 2.5, height: 4 + 12 * (wave + 1) / 2)
            }
        }
    }
}

private struct DemoCursor: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: 17))
            path.addLine(to: CGPoint(x: 4.5, y: 13))
            path.addLine(to: CGPoint(x: 7.5, y: 20))
            path.addLine(to: CGPoint(x: 10.5, y: 18.8))
            path.addLine(to: CGPoint(x: 7.5, y: 12))
            path.addLine(to: CGPoint(x: 13, y: 12))
            path.closeSubpath()
        }
        .fill(.black)
        .overlay {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 17))
                path.addLine(to: CGPoint(x: 4.5, y: 13))
                path.addLine(to: CGPoint(x: 7.5, y: 20))
                path.addLine(to: CGPoint(x: 10.5, y: 18.8))
                path.addLine(to: CGPoint(x: 7.5, y: 12))
                path.addLine(to: CGPoint(x: 13, y: 12))
                path.closeSubpath()
            }
            .stroke(.white, lineWidth: 1.2)
        }
        .frame(width: 14, height: 21)
    }
}

/// A plain backdrop with the notch on it. `open` runs 0 (closed) to 1 (open) and may overshoot.
private struct DemoStage: View {
    static let size = CGSize(width: 800, height: 300)

    @ObservedObject var controller: NotchController
    let open: Double
    var cursor: CGPoint?

    private func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * open }

    var body: some View {
        let notch = controller.notchSize
        let full = NotchController.expandedSize
        let top = max(mix(8, 14), 0)
        let bottom = max(mix(12, 30), 0)
        let width = mix(notch.width + CompactActivity.media.wing * 2, full.width)
        let height = mix(notch.height, full.height)

        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(red: 0.13, green: 0.16, blue: 0.3), Color(red: 0.05, green: 0.06, blue: 0.13)],
                startPoint: .top, endPoint: .bottom
            )
            Rectangle().fill(.white.opacity(0.07)).frame(height: notch.height)

            ZStack(alignment: .top) {
                ExpandedView(controller: controller, system: controller.system)
                    .frame(width: full.width, height: full.height)
                    .opacity(max((open - 0.45) / 0.55, 0))
                CompactView(
                    activity: .media,
                    notchWidth: notch.width,
                    media: controller.media, timer: controller.timer, system: controller.system, fans: controller.fans
                )
                .frame(width: notch.width + CompactActivity.media.wing * 2, height: notch.height)
                .opacity(max(1 - open * 3, 0))
            }
            .frame(width: width, height: height, alignment: .top)
            .padding(.horizontal, top)
            .background(Color.black)
            .clipShape(NotchShape(topRadius: top, bottomRadius: bottom))
            .shadow(color: .black.opacity(0.5 * min(max(open, 0), 1)), radius: 18, y: 8)
            .frame(width: Self.size.width, alignment: .top)

            if let cursor {
                DemoCursor().offset(x: cursor.x, y: cursor.y)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .clipped()
        .environment(\.colorScheme, .dark)
    }
}

final class DemoCapture {
    // The demo binary has no app bundle, so it takes its version and icon from the repo.
    static let version = (try? String(contentsOfFile: "VERSION", encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    private let controller: NotchController
    private let directory: URL
    private let window: NSWindow
    private let hosting: NSHostingView<DemoStage>

    init(controller: NotchController, directory: String) {
        self.controller = controller
        self.directory = URL(fileURLWithPath: directory)
        let rect = NSRect(origin: CGPoint(x: -6000, y: -6000), size: DemoStage.size)
        window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        hosting = NSHostingView(rootView: DemoStage(controller: controller, open: 0))
        hosting.frame = NSRect(origin: .zero, size: DemoStage.size)
        window.contentView = hosting
        window.orderFrontRegardless()
    }

    func run() {
        controller.hidePanelForDemo()
        NSApp.applicationIconImage = NSImage(contentsOfFile: "docs/images/logo.png")
        controller.media.loadDemo(artwork: Self.makeArtwork())
        controller.timer.loadDemo()
        controller.system.loadDemo()
        controller.fans.loadDemo()
        controller.shelf.loadDemo(Self.makeShelfFiles())
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        settle(1)
        writePNG(frame(open: 0), name: "closed.png")
        for tab in NotchTab.allCases {
            controller.tab = tab
            hosting.rootView = DemoStage(controller: controller, open: 1)
            settle(1)
            writePNG(frame(open: 1), name: "\(tab.rawValue).png")
        }
        writeGIF()
        NSApp.terminate(nil)
    }

    /// Every state of the Thermals tab, for checking the design. Not used in the README.
    func runThermalsStates() {
        controller.hidePanelForDemo()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        controller.tab = .thermals
        let states: [(String, FanModel.Mode, Bool, Bool, Bool)] = [
            ("automatic", .automatic, false, false, false),
            ("manual", .manual, false, false, false),
            ("max", .max, false, false, false),
            ("fanless", .automatic, true, false, false),
            ("experimental-manual", .manual, false, true, false),
            ("experimental-setup", .automatic, false, true, true),
        ]
        for (name, mode, fanless, experimental, needsHelper) in states {
            controller.fans.loadDemo(mode: mode, fanless: fanless, experimental: experimental, needsHelper: needsHelper)
            hosting.rootView = DemoStage(controller: controller, open: 1)
            settle(0.8)
            writePNG(frame(open: 1), name: "thermals-\(name).png")
        }
        NSApp.terminate(nil)
    }

    private func settle(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        hosting.layoutSubtreeIfNeeded()
    }

    private func frame(open: Double, cursor: CGPoint? = nil, scale: CGFloat = 2) -> NSBitmapImageRep {
        hosting.rootView = DemoStage(controller: controller, open: open, cursor: cursor)
        settle(0.02)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(DemoStage.size.width * scale), pixelsHigh: Int(DemoStage.size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = DemoStage.size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
    }

    private func writePNG(_ rep: NSBitmapImageRep, name: String) {
        try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name))
    }

    // MARK: - GIF

    private struct Beat {
        var seconds: Double
        var tab: NotchTab?
        var cursorTo: CGPoint?
        var openTo: Double?
    }

    private func writeGIF() {
        let fps = 20.0
        let tabX: [NotchTab: CGFloat] = [.media: 146, .timer: 175, .shelf: 204, .system: 233, .thermals: 262, .credits: 291]
        let tabY: CGFloat = 12
        let beats: [Beat] = [
            Beat(seconds: 1.0),
            Beat(seconds: 0.8, cursorTo: CGPoint(x: 410, y: 10)),
            Beat(seconds: 2.0, openTo: 1),
            Beat(seconds: 0.4, cursorTo: CGPoint(x: tabX[.timer]!, y: tabY)),
            Beat(seconds: 1.5, tab: .timer),
            Beat(seconds: 0.3, cursorTo: CGPoint(x: tabX[.shelf]!, y: tabY)),
            Beat(seconds: 1.5, tab: .shelf),
            Beat(seconds: 0.3, cursorTo: CGPoint(x: tabX[.system]!, y: tabY)),
            Beat(seconds: 1.5, tab: .system),
            Beat(seconds: 0.3, cursorTo: CGPoint(x: tabX[.thermals]!, y: tabY)),
            Beat(seconds: 1.8, tab: .thermals),
            Beat(seconds: 0.3, cursorTo: CGPoint(x: tabX[.credits]!, y: tabY)),
            Beat(seconds: 1.8, tab: .credits),
            Beat(seconds: 0.6, cursorTo: CGPoint(x: 640, y: 285)),
            Beat(seconds: 1.0, tab: .media, openTo: 0),
        ]

        let url = directory.appendingPathComponent("demo.gif") as CFURL
        let total = beats.reduce(0) { $0 + Int($1.seconds * fps) }
        guard let destination = CGImageDestinationCreateWithURL(url, UTType.gif.identifier as CFString, total, nil) else { return }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps],
        ] as CFDictionary

        var time = 0.0
        var cursor = CGPoint(x: 600, y: 240)
        var open = 0.0
        controller.tab = .media
        for beat in beats {
            let count = Int(beat.seconds * fps)
            let cursorStart = cursor
            let openStart = open
            for index in 0..<count {
                if index == 0, let tab = beat.tab, beat.openTo == nil { controller.tab = tab }
                let t = Double(index + 1) / Double(count)
                if let target = beat.cursorTo {
                    let eased = t * t * (3 - 2 * t)
                    cursor = CGPoint(
                        x: cursorStart.x + (target.x - cursorStart.x) * eased,
                        y: cursorStart.y + (target.y - cursorStart.y) * eased
                    )
                }
                if let target = beat.openTo {
                    // The app's own spring, as a closed form: settles in about 0.6 s, with a little overshoot.
                    let elapsed = Double(index + 1) / fps
                    let spring = 1 - exp(-7 * elapsed) * cos(11 * elapsed)
                    open = openStart + (target - openStart) * spring
                }
                time += 1 / fps
                DemoClock.shared.time = time
                let rep = frame(open: open, cursor: cursor, scale: 1.25)
                if let image = rep.cgImage {
                    CGImageDestinationAddImage(destination, image, frameProperties)
                }
            }
        }
        CGImageDestinationFinalize(destination)
    }

    // MARK: - Made-up content

    private static func makeArtwork() -> NSImage {
        NSImage(size: NSSize(width: 400, height: 400), flipped: false) { rect in
            NSGradient(colors: [
                NSColor(srgbRed: 0.98, green: 0.35, blue: 0.55, alpha: 1),
                NSColor(srgbRed: 0.35, green: 0.16, blue: 0.75, alpha: 1),
                NSColor(srgbRed: 0.06, green: 0.08, blue: 0.3, alpha: 1),
            ])?.draw(in: rect, angle: -90)
            NSColor(srgbRed: 1, green: 0.8, blue: 0.45, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 110, y: 150, width: 180, height: 180)).fill()
            NSColor(srgbRed: 0.06, green: 0.08, blue: 0.3, alpha: 1).setFill()
            for (index, y) in stride(from: 160.0, to: 250.0, by: 24.0).enumerated() {
                NSBezierPath(rect: NSRect(x: 100, y: y, width: 200, height: 3.0 + Double(3 - index) * 2)).fill()
            }
            return true
        }
    }

    private static func makeShelfFiles() -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notchutils-demo", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return ["Launch Plan.pdf", "Hero Shot.png", "Release Notes.md", "Budget.xlsx", "Assets.zip"].map { name in
            let url = folder.appendingPathComponent(name)
            FileManager.default.createFile(atPath: url.path, contents: Data())
            return url
        }
    }
}
#endif
