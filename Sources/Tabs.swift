// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Rupaj Sen

import QuickLookThumbnailing
import SwiftUI

// MARK: - Now Playing

struct MediaTab: View {
    @ObservedObject var media: MediaModel

    var body: some View {
        if let track = media.track, let source = media.source {
            HStack(spacing: 16) {
                Button { media.open(source) } label: {
                    ArtworkView(image: media.artwork, cornerRadius: 14)
                        .frame(width: 136, height: 136)
                        .shadow(color: media.accent.opacity(0.35), radius: 14)
                }
                .buttonStyle(PressableStyle())
                .help("Open \(source.rawValue)")
                .accessibilityLabel("Open \(source.rawValue)")

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let position = media.position(at: context.date)
                        VStack(spacing: 2) {
                            CapsuleSlider(
                                value: position,
                                range: 0...max(track.duration, 1),
                                tint: media.accent,
                                onChange: { _ in },
                                onCommit: { media.seek(to: $0) }
                            )
                            HStack {
                                Text(clockString(position))
                                Spacer()
                                Text("-" + clockString(max(track.duration - position, 0)))
                            }
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 4)
                    HStack(spacing: 22) {
                        TransportButton(symbol: "backward.fill", size: 18, label: "Previous") { media.previous() }
                        TransportButton(
                            symbol: media.isPlaying ? "pause.fill" : "play.fill",
                            size: 26,
                            label: media.isPlaying ? "Pause" : "Play"
                        ) { media.playPause() }
                        TransportButton(symbol: "forward.fill", size: 18, label: "Next") { media.next() }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if media.needsPermission {
            EmptyStateView(
                symbol: "lock.fill",
                title: "NotchUtils can't see your music yet",
                detail: "Allow it under Automation in System Settings."
            ) {
                CapsuleButton(title: "Open Settings", symbol: "gear") { media.openAutomationSettings() }
            }
        } else {
            EmptyStateView(symbol: "music.note", title: "Nothing playing", detail: "Start something in Spotify or Music.") {
                ForEach(MediaSource.allCases.filter { $0.appURL != nil }, id: \.self) { source in
                    CapsuleButton(title: source.rawValue, symbol: "arrow.up.forward.app") { media.open(source) }
                }
            }
        }
    }
}

struct TransportButton: View {
    let symbol: String
    let size: CGFloat
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 40, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

struct CapsuleButton: View {
    let title: String
    var symbol: String?
    var isProminent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                if let symbol { Image(systemName: symbol) }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isProminent ? .black : .white)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(isProminent ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.14))))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

struct EmptyStateView<Actions: View>: View {
    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            HStack(spacing: 8) { actions }.padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Timer

struct TimerTab: View {
    @ObservedObject var timer: TimerModel
    private let presets = [5, 15, 25, 45]

    var body: some View {
        HStack(spacing: 24) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ZStack {
                    Circle().stroke(.white.opacity(0.14), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: timer.progress(at: context.date))
                        .stroke(.orange, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: context.date)
                    Text(clockString(timer.remaining(at: context.date)))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                }
            }
            .frame(width: 128, height: 128)
            .padding(.leading, 8)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { minutes in
                        let selected = timer.state == .idle && timer.duration == TimeInterval(minutes * 60)
                        CapsuleButton(title: "\(minutes)m", isProminent: selected) {
                            timer.select(minutes: minutes)
                        }
                    }
                }
                HStack(spacing: 8) {
                    CapsuleButton(title: "1 min", symbol: "minus") { timer.adjust(minutes: -1) }
                    CapsuleButton(title: "1 min", symbol: "plus") { timer.adjust(minutes: 1) }
                }
                HStack(spacing: 8) {
                    CapsuleButton(
                        title: timer.state == .running ? "Pause" : (timer.state == .paused ? "Resume" : "Start"),
                        symbol: timer.state == .running ? "pause.fill" : "play.fill",
                        isProminent: true
                    ) { timer.toggle() }
                    if timer.state != .idle {
                        CapsuleButton(title: "Reset", symbol: "arrow.counterclockwise") { timer.reset() }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Shelf

struct ShelfTab: View {
    @ObservedObject var shelf: ShelfModel
    let isTargeted: Bool

    var body: some View {
        Group {
            if shelf.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(isTargeted ? .white : .secondary)
                        .symbolEffect(.bounce, value: isTargeted)
                    Text("Drop files here").font(.system(size: 14, weight: .semibold))
                    Text("Keep them handy, then drag them out wherever you need them.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(dropOutline)
            } else {
                VStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(shelf.items, id: \.self) { url in
                                ShelfItemView(url: url) { shelf.remove(url) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: .infinity)
                    .background(dropOutline)
                    HStack(spacing: 8) {
                        Text("^[\(shelf.items.count) item](inflect: true)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        CapsuleButton(title: "AirDrop", symbol: "airplayaudio") { shelf.airDrop() }
                        CapsuleButton(title: "Clear", symbol: "xmark") { shelf.clear() }
                    }
                }
            }
        }
    }

    private var dropOutline: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(
                isTargeted ? Color.white.opacity(0.7) : Color.white.opacity(shelf.items.isEmpty ? 0.2 : 0),
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
            )
    }
}

struct ShelfItemView: View {
    let url: URL
    let remove: () -> Void

    @StateObject private var thumbnail = ViewState<NSImage?>(nil)
    @StateObject private var isHovering = ViewState(false)

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: thumbnail.value ?? NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
            Text(url.lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(height: 26, alignment: .top)
        }
        .frame(width: 84, height: 92)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(isHovering.value ? 0.12 : 0))
        )
        .overlay(alignment: .topTrailing) {
            if isHovering.value {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(PressableStyle())
                .padding(3)
                .accessibilityLabel("Remove \(url.lastPathComponent)")
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering.value = $0 }
        .onTapGesture { NSWorkspace.shared.open(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .help(url.path)
        .task(id: url) {
            let request = QLThumbnailGenerator.Request(
                fileAt: url, size: CGSize(width: 52, height: 52), scale: 2, representationTypes: .thumbnail
            )
            thumbnail.value = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
        }
    }
}

// MARK: - System

struct SystemTab: View {
    @ObservedObject var system: SystemModel
    let quit: () -> Void

    var body: some View {
        HStack(spacing: 20) {
            VStack(spacing: 14) {
                HStack(spacing: 0) {
                    Meter(title: "Battery", value: system.batteryLevel, tint: system.batteryLevel < 0.2 ? .red : .green)
                    Meter(title: "CPU", value: system.cpu, tint: .blue)
                    Meter(title: "Memory", value: system.memory, tint: .purple)
                    Meter(title: "Storage", value: system.storage, tint: .orange)
                }
                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    CapsuleSlider(
                        value: system.volume ?? 0,
                        onChange: { system.setVolume($0) }
                    )
                    .disabled(system.volume == nil)
                    .opacity(system.volume == nil ? 0.4 : 1)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Text(batteryCaption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)

            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    QuickAction(title: "Keep Awake", symbol: "cup.and.heat.waves.fill", isOn: system.keepAwake, action: system.toggleKeepAwake)
                    QuickAction(title: "Screenshot", symbol: "camera.viewfinder", action: system.takeScreenshot)
                }
                GridRow {
                    QuickAction(title: "Sleep Display", symbol: "moon.fill", action: system.sleepDisplay)
                    QuickAction(title: "Open at Login", symbol: "power", isOn: system.opensAtLogin, action: system.toggleOpenAtLogin)
                }
                GridRow {
                    QuickAction(title: "Quit", symbol: "xmark", action: quit)
                        .gridCellColumns(2)
                }
            }
            .frame(width: 236)
        }
        .onAppear { system.startSampling() }
        .onDisappear { system.stopSampling() }
    }

    private var batteryCaption: String {
        // HDMI and some USB outputs leave volume to the device itself.
        if system.volume == nil { return "This output's volume is set on the device" }
        if system.isCharging { return "Charging" }
        if system.isOnPower { return "On power adapter" }
        if let minutes = system.minutesToEmpty {
            return "\(minutes / 60)h \(minutes % 60)m of battery left"
        }
        return "On battery"
    }
}

struct Meter: View {
    let title: String
    let value: Double
    let tint: Color

    var body: some View {
        VStack(spacing: 5) {
            Gauge(value: min(max(value, 0), 1)) {
                EmptyView()
            } currentValueLabel: {
                Text(Int((value * 100).rounded()), format: .number)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(tint)
            .scaleEffect(0.86)
            .frame(width: 50, height: 50)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
    }
}

struct QuickAction: View {
    let title: String
    let symbol: String
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isOn ? .black : .white)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.12)))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Credits

struct CreditsTab: View {
    private var version: String {
        #if DEMO
        DemoCapture.version
        #else
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        #endif
    }

    var body: some View {
        HStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 124, height: 124)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("NotchUtils")
                            .font(.system(size: 22, weight: .bold))
                        Text("Version \(version)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Text("Your notch, put to work.")
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)
                }

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                    CreditRow(label: "Created by", value: "Rupaj Sen")
                    CreditRow(label: "Built with", value: "Claude Opus 5.5, by Anthropic")
                    CreditRow(label: "Created on", value: "November 1, 2026")
                    CreditRow(label: "License", value: "MIT, © 2026 Rupaj Sen")
                }

                HStack(spacing: 8) {
                    CapsuleButton(title: "View on GitHub", symbol: "chevron.left.forwardslash.chevron.right") {
                        open("https://github.com/rupajsen/NotchUtils")
                    }
                    CapsuleButton(title: "Suggest an Idea", symbol: "lightbulb.fill") {
                        open("https://github.com/rupajsen/NotchUtils/discussions/categories/ideas")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private func open(_ address: String) {
    if let url = URL(string: address) { NSWorkspace.shared.open(url) }
}

struct CreditRow: View {
    let label: String
    let value: String

    var body: some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
        }
        .font(.system(size: 12))
    }
}
