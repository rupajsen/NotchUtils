// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Rupaj Sen

import SwiftUI

struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let t = topRadius, b = bottomRadius
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + t, y: rect.minY + t),
            control: CGPoint(x: rect.minX + t, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
            control: CGPoint(x: rect.minX + t, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
            control: CGPoint(x: rect.maxX - t, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - t, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

struct NotchRootView: View {
    @ObservedObject var controller: NotchController
    @ObservedObject var media: MediaModel
    @ObservedObject var timer: TimerModel
    @ObservedObject var system: SystemModel
    @ObservedObject var fans: FanModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.78)
    }

    var body: some View {
        let size = controller.shapeSize
        let radii = controller.radii

        ZStack(alignment: .top) {
            if controller.isExpanded {
                ExpandedView(controller: controller, system: system)
                    .frame(width: NotchController.expandedSize.width, height: NotchController.expandedSize.height)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
            } else if controller.activity != .none {
                CompactView(
                    activity: controller.activity,
                    notchWidth: controller.notchSize.width,
                    media: media, timer: timer, system: system, fans: fans
                )
                .frame(height: controller.notchSize.height)
                .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .padding(.horizontal, radii.top)
        .background(Color.black)
        .clipShape(NotchShape(topRadius: radii.top, bottomRadius: radii.bottom))
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $controller.isDropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.isFileURL else { return }
                    DispatchQueue.main.async { controller.shelf.add([url]) }
                }
            }
            return true
        }
        .shadow(color: .black.opacity(controller.isExpanded ? 0.55 : 0), radius: 18, y: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(animation, value: controller.isExpanded)
        .animation(animation, value: controller.activity)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Closed notch

struct CompactView: View {
    let activity: CompactActivity
    let notchWidth: CGFloat
    @ObservedObject var media: MediaModel
    @ObservedObject var timer: TimerModel
    @ObservedObject var system: SystemModel
    @ObservedObject var fans: FanModel

    var body: some View {
        HStack(spacing: 0) {
            leading.frame(maxWidth: .infinity)
            Color.clear.frame(width: notchWidth)
            trailing.frame(maxWidth: .infinity)
        }
        .font(.system(size: 13, weight: .semibold))
    }

    @ViewBuilder private var leading: some View {
        switch activity {
        case .media:
            ArtworkView(image: media.artwork, cornerRadius: 5)
                .frame(width: 22, height: 22)
        case .timer:
            Image(systemName: timer.state == .paused ? "pause.fill" : "timer")
                .foregroundStyle(.orange)
        case .timerDone:
            Image(systemName: "bell.fill")
                .foregroundStyle(.orange)
                .symbolEffect(.wiggle, options: .repeat(3))
        case .charging:
            Image(systemName: "bolt.fill")
                .foregroundStyle(.green)
                .symbolEffect(.pulse)
        case .awake:
            Image(systemName: "cup.and.heat.waves.fill")
                .foregroundStyle(.yellow)
        case .fans:
            Image(systemName: "fan.fill")
                .foregroundStyle(.cyan)
        case .fansReverted:
            Image(systemName: "fan.fill")
                .foregroundStyle(.white)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder private var trailing: some View {
        switch activity {
        case .media:
            #if DEMO
            DemoBars(color: media.accent)
                .frame(width: 20, height: 16)
            #else
            AudioBars(color: NSColor(media.accent), isAnimating: media.isPlaying)
                .frame(width: 20, height: 16)
            #endif
        case .timer:
            if timer.state == .running {
                Text(timerInterval: Date()...timer.endDate, countsDown: true)
                    .monospacedDigit()
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            } else {
                Text(clockString(timer.remaining()))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
            }
        case .timerDone:
            Text("Done").foregroundStyle(.orange)
        case .charging:
            Text(system.batteryLevel, format: .percent.precision(.fractionLength(0)))
                .monospacedDigit()
                .foregroundStyle(.green)
        case .fans:
            Text(fans.averageRPM / 1000, format: .number.precision(.fractionLength(1)))
                .monospacedDigit()
                .foregroundStyle(.cyan)
                + Text("k").foregroundStyle(.cyan)
        case .fansReverted:
            Text("Auto")
        case .awake, .none:
            EmptyView()
        }
    }
}

/// Decorative, since apps can't read another app's audio levels without recording it. Built on
/// Core Animation because the render server runs it: an SF Symbol effect here redraws SwiftUI every
/// frame and costs about 15% CPU the whole time music plays.
struct AudioBars: NSViewRepresentable {
    let color: NSColor
    let isAnimating: Bool

    private static let durations: [CFTimeInterval] = [0.47, 0.71, 0.39, 0.59]

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        for _ in Self.durations {
            let bar = CALayer()
            bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            bar.cornerRadius = 1.25
            view.layer?.addSublayer(bar)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let bars = view.layer?.sublayers else { return }
        let height = max(view.bounds.height, 16)
        let width = max(view.bounds.width, 20)
        let step = width / CGFloat(bars.count)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.backgroundColor = color.cgColor
            bar.bounds = CGRect(x: 0, y: 0, width: 2.5, height: height)
            bar.position = CGPoint(x: step * (CGFloat(index) + 0.5), y: height / 2)
            if isAnimating {
                guard bar.animation(forKey: "level") == nil else { continue }
                let level = CABasicAnimation(keyPath: "transform.scale.y")
                level.fromValue = 0.25
                level.toValue = 1
                level.duration = Self.durations[index]
                level.autoreverses = true
                level.repeatCount = .infinity
                level.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                bar.add(level, forKey: "level")
            } else {
                bar.removeAnimation(forKey: "level")
                bar.transform = CATransform3DMakeScale(1, 0.25, 1)
            }
        }
        CATransaction.commit()
    }
}

func clockString(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded(.up))
    let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
    return h > 0
        ? String(format: "%d:%02d:%02d", h, m, s)
        : String(format: "%d:%02d", m, s)
}

// MARK: - Open notch

struct ExpandedView: View {
    @ObservedObject var controller: NotchController
    @ObservedObject var system: SystemModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TabBar(selection: $controller.tab)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: controller.notchSize.width)
                StatusCluster(controller: controller, system: system)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: max(controller.notchSize.height, 32))
            .padding(.horizontal, 22)

            Group {
                switch controller.tab {
                case .media: MediaTab(media: controller.media)
                case .timer: TimerTab(timer: controller.timer)
                case .shelf: ShelfTab(shelf: controller.shelf, isTargeted: controller.isDropTargeted)
                case .system: SystemTab(system: system, quit: controller.quit)
                case .thermals: ThermalsTab(fans: controller.fans)
                case .credits: CreditsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 18)
            .transition(.opacity)
        }
    }
}

struct TabBar: View {
    @Binding var selection: NotchTab
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(NotchTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = tab }
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selection == tab ? .white : .secondary)
                        .frame(width: 27, height: 24)
                        .background {
                            if selection == tab {
                                Capsule().fill(.white.opacity(0.18))
                                    .matchedGeometryEffect(id: "tab", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .help(tab.title)
                .accessibilityLabel(tab.title)
            }
        }
    }
}

struct StatusCluster: View {
    @ObservedObject var controller: NotchController
    @ObservedObject var system: SystemModel

    var body: some View {
        HStack(spacing: 8) {
            #if DEMO
            Text("9:41 AM")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .fixedSize()
            #else
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .fixedSize()
            }
            #endif
            HStack(spacing: 4) {
                Text(system.batteryLevel, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .fixedSize()
                Image(systemName: system.batterySymbol)
                    .font(.system(size: 13))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(system.isOnPower ? .green : (system.batteryLevel < 0.2 ? .red : .white))
            }
            Button {
                controller.isPinned.toggle()
            } label: {
                Image(systemName: controller.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(controller.isPinned ? .white : .secondary)
                    .frame(width: 20, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .help(controller.isPinned ? "Unpin" : "Keep open")
            .accessibilityLabel(controller.isPinned ? "Unpin" : "Keep open")
        }
    }
}

// MARK: - Shared controls

/// Stands in for @State, which is a macro in the macOS 27 SDK whose plugin ships only with Xcode,
/// so this project wouldn't build with just the Command Line Tools.
final class ViewState<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.1)
                    Image(systemName: "music.note").foregroundStyle(.secondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// AppKit's NSSlider draws as disabled in a window that isn't key, and this panel never takes
/// key focus from the app you're working in, so the slider is drawn in SwiftUI.
struct CapsuleSlider: View {
    let value: Double
    var range: ClosedRange<Double> = 0...1
    var tint: Color = .white
    var showsThumb = false
    let onChange: (Double) -> Void
    var onCommit: (Double) -> Void = { _ in }

    @StateObject private var isHovering = ViewState(false)
    @StateObject private var dragValue = ViewState<Double?>(nil)

    var body: some View {
        GeometryReader { geometry in
            let shown = dragValue.value ?? value
            let span = max(range.upperBound - range.lowerBound, 0.001)
            let fraction = min(max((shown - range.lowerBound) / span, 0), 1)
            let active = isHovering.value || dragValue.value != nil
            let thumbWidth: CGFloat = 24
            ZStack(alignment: .leading) {
                Group {
                    Capsule().fill(.white.opacity(0.22))
                    Capsule().fill(showsThumb || active ? tint : tint.opacity(0.85))
                        .frame(width: max(geometry.size.width * fraction, 0))
                }
                .frame(height: showsThumb ? 5 : (active ? 8 : 5))

                if showsThumb {
                    Capsule()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .frame(width: thumbWidth, height: 15)
                        .scaleEffect(dragValue.value == nil ? 1 : 1.12)
                        .offset(x: (geometry.size.width - thumbWidth) * fraction)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: active)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let f = min(max(gesture.location.x / max(geometry.size.width, 1), 0), 1)
                        let newValue = range.lowerBound + f * span
                        dragValue.value = newValue
                        onChange(newValue)
                    }
                    .onEnded { _ in
                        if let last = dragValue.value { onCommit(last) }
                        dragValue.value = nil
                    }
            )
            .onHover { isHovering.value = $0 }
        }
        .frame(height: 16)
    }
}
