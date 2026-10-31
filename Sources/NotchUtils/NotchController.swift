// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Rupaj Sen

import AppKit
import OSLog
import SwiftUI

private let log = Logger(subsystem: "io.github.rupajsen.notchutils", category: "notch")

enum NotchTab: String, CaseIterable, Identifiable {
    case media, timer, shelf, system, thermals, credits

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .media: "play.fill"
        case .timer: "timer"
        case .shelf: "tray.full.fill"
        case .system: "slider.horizontal.3"
        case .thermals: "thermometer.medium"
        case .credits: "info.circle.fill"
        }
    }

    var title: String {
        switch self {
        case .media: "Now Playing"
        case .timer: "Timer"
        case .shelf: "Shelf"
        case .system: "System"
        case .thermals: "Thermals"
        case .credits: "Credits"
        }
    }
}

/// What the closed notch is showing in its "wings", most urgent first.
enum CompactActivity: Equatable {
    case none, awake, media, fans, fansReverted, timer, charging, timerDone

    var wing: CGFloat {
        switch self {
        case .none: 0
        case .awake, .media: 34
        case .charging: 50
        case .timer, .timerDone, .fans, .fansReverted: 62
        }
    }
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // Without this, AppKit pushes the panel out of the menu bar area.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class NotchController: ObservableObject {
    static let expandedSize = CGSize(width: 580, height: 224)
    private static let panelSize = CGSize(width: 700, height: 300)

    @Published var isExpanded = false
    @Published var isPinned = false
    @Published var tab: NotchTab = .media {
        didSet { log.notice("tab=\(self.tab.rawValue, privacy: .public)") }
    }
    @Published var isDropTargeted = false {
        didSet { if isDropTargeted { tab = .shelf } }
    }
    @Published private(set) var transient: CompactActivity?
    @Published private(set) var notchSize = CGSize(width: 185, height: 32)

    let media = MediaModel()
    let timer = TimerModel()
    let shelf = ShelfModel()
    let system = SystemModel()
    let fans = FanModel()

    private var panel: NotchPanel!
    private var notchCenterX: CGFloat = 0
    private var screenTop: CGFloat = 0
    private var hasNotchScreen = false
    private var monitors: [Any] = []
    private var trackingTimer: Timer?
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var transientWork: DispatchWorkItem?
    private var dragChangeCount = 0

    init(pinnedTab: NotchTab?) {
        panel = makePanel()
        layoutOnNotchScreen()
        installMonitors()

        timer.onFinished = { [weak self] in
            NSSound(named: "Glass")?.play()
            self?.show(transient: .timerDone, for: 5)
        }
        system.onPluggedIn = { [weak self] in
            self?.show(transient: .charging, for: 3)
        }
        fans.onReverted = { [weak self] in
            self?.show(transient: .fansReverted, for: 5)
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.layoutOnNotchScreen() }

        if let pinnedTab {
            tab = pinnedTab
            isPinned = true
            setExpanded(true)
            panel.ignoresMouseEvents = false
        }
    }

    var activity: CompactActivity {
        if let transient { return transient }
        if timer.state != .idle { return .timer }
        if fans.isManual { return .fans }
        if media.isPlaying { return .media }
        if system.keepAwake { return .awake }
        return .none
    }

    /// Size of the black shape, not counting its flared top corners.
    var shapeSize: CGSize {
        if isExpanded { return Self.expandedSize }
        let wing = activity.wing
        // Idle, the shape sits just inside the real notch so it stays invisible.
        if wing == 0 { return CGSize(width: notchSize.width - 4, height: notchSize.height - 1) }
        return CGSize(width: notchSize.width + wing * 2, height: notchSize.height)
    }

    var radii: (top: CGFloat, bottom: CGFloat) {
        if isExpanded { return (14, 30) }
        return activity == .none ? (0, 8) : (8, 12)
    }

    func quit() { NSApp.terminate(nil) }

    #if DEMO
    /// The demo build draws into its own offscreen window, so the live panel stays out of the way.
    func hidePanelForDemo() {
        hasNotchScreen = false
        panel.orderOut(nil)
    }
    #endif

    /// Renders the panel to a PNG, for checking layout without Screen Recording permission.
    func writeSnapshot(to path: String) {
        guard let view = panel.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    // MARK: - Window

    private func makePanel() -> NotchPanel {
        let panel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .mainMenu + 3
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.appearance = NSAppearance(named: .darkAqua)

        let root = NotchRootView(controller: self, media: media, timer: timer, system: system, fans: fans)
        panel.contentView = NotchHostingView(rootView: root)
        return panel
    }

    private func layoutOnNotchScreen() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else {
            // Lid closed, so there is no notch to live in.
            hasNotchScreen = false
            panel.orderOut(nil)
            return
        }
        hasNotchScreen = true
        notchSize = CGSize(
            width: screen.frame.width - left.width - right.width,
            height: screen.safeAreaInsets.top
        )
        notchCenterX = screen.frame.minX + left.width + notchSize.width / 2
        screenTop = screen.frame.maxY
        log.notice("notch \(self.notchSize.width)x\(self.notchSize.height) centerX=\(self.notchCenterX) top=\(self.screenTop)")
        panel.setFrame(
            NSRect(
                x: notchCenterX - Self.panelSize.width / 2,
                y: screenTop - Self.panelSize.height,
                width: Self.panelSize.width,
                height: Self.panelSize.height
            ),
            display: true
        )
        panel.orderFrontRegardless()
    }

    // MARK: - Hover

    private func installMonitors() {
        let tracked: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: tracked, handler: { [weak self] event in
            guard let self else { return }
            if event.type == .leftMouseDown {
                self.dragChangeCount = NSPasteboard(name: .drag).changeCount
            }
            self.handleMouse()
        }) {
            monitors.append(monitor)
        }
    }

    private var activeRect: NSRect {
        let size = shapeSize
        let radius = radii.top
        let width = max(size.width, notchSize.width) + radius * 2
        let height = max(size.height, notchSize.height)
        let slack: CGFloat = isExpanded ? 6 : 2
        return NSRect(
            x: notchCenterX - width / 2 - slack,
            y: screenTop - height - slack,
            width: width + slack * 2,
            // Extends above the screen because the top row of pixels sits on the rect's excluded edge.
            height: height + slack + 2
        )
    }

    /// True while Finder (or another app) is dragging files.
    private var isDraggingFiles: Bool {
        guard NSEvent.pressedMouseButtons & 1 != 0 else { return false }
        let pasteboard = NSPasteboard(name: .drag)
        return pasteboard.changeCount != dragChangeCount
            && pasteboard.types?.contains(.fileURL) == true
    }

    private func handleMouse() {
        guard hasNotchScreen else { return }
        let inside = activeRect.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        updateTrackingTimer(inside: inside)

        if inside {
            collapseWork?.cancel()
            collapseWork = nil
            guard !isExpanded, expandWork == nil else { return }
            let pressed = NSEvent.pressedMouseButtons != 0
            // A window or text drag that wanders into the notch shouldn't open it.
            guard !pressed || isDraggingFiles else { return }
            if isDraggingFiles { tab = .shelf }
            schedule(&expandWork, after: 0.09) { [weak self] in
                self?.expandWork = nil
                self?.setExpanded(true)
            }
        } else {
            expandWork?.cancel()
            expandWork = nil
            guard isExpanded, !isPinned, collapseWork == nil, NSEvent.pressedMouseButtons == 0 else { return }
            schedule(&collapseWork, after: 0.3) { [weak self] in
                self?.collapseWork = nil
                self?.setExpanded(false)
            }
        }
    }

    private func schedule(_ slot: inout DispatchWorkItem?, after delay: TimeInterval, _ body: @escaping () -> Void) {
        let work = DispatchWorkItem(block: body)
        slot = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Global monitors stop firing once the cursor is over our own window, so poll while it's there.
    private func updateTrackingTimer(inside: Bool) {
        let needed = inside || isExpanded
        if needed, trackingTimer == nil {
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.handleMouse() }
            RunLoop.main.add(timer, forMode: .common)
            trackingTimer = timer
        } else if !needed, let timer = trackingTimer {
            timer.invalidate()
            trackingTimer = nil
        }
    }

    private func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        log.notice("expanded=\(expanded) tab=\(self.tab.rawValue, privacy: .public)")
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        if expanded {
            media.refresh()
            updateTrackingTimer(inside: true)
        }
    }

    private func show(transient activity: CompactActivity, for seconds: TimeInterval) {
        transient = activity
        transientWork?.cancel()
        schedule(&transientWork, after: seconds) { [weak self] in self?.transient = nil }
    }
}
