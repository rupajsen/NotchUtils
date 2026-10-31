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
    var suffix = ""
    var spokenValue: String?

    var body: some View {
        VStack(spacing: 5) {
            Gauge(value: min(max(value, 0), 1)) {
                EmptyView()
            } currentValueLabel: {
                Text("\(Int((value * 100).rounded()))\(suffix)")
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
        .accessibilityValue(spokenValue.map { Text($0) } ?? Text(value, format: .percent.precision(.fractionLength(0))))
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

// MARK: - Thermals

struct ThermalsTab: View {
    @ObservedObject var fans: FanModel

    var body: some View {
        Group {
            if fans.availability == .noFans {
                fanlessLayout
            } else {
                HStack(spacing: 16) {
                    Grid(horizontalSpacing: 0, verticalSpacing: 8) {
                        ForEach(Array(stride(from: 0, to: fans.readings.count, by: 2)), id: \.self) { start in
                            GridRow {
                                ForEach(fans.readings[start..<min(start + 2, fans.readings.count)]) {
                                    TemperatureMeter(reading: $0)
                                }
                            }
                        }
                    }
                    .frame(width: 148)
                    .frame(maxHeight: .infinity, alignment: .top)

                    fanColumn.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .onAppear { fans.startMonitoring() }
        .onDisappear { fans.stopMonitoring() }
    }

    /// Macs without fans get the temperatures on their own, with nothing that hints at a missing feature.
    private var fanlessLayout: some View {
        VStack(spacing: 14) {
            if fans.readings.isEmpty {
                ThermalsNote(symbol: "thermometer.medium.slash", text: "Temperatures aren't available on this Mac.")
            } else {
                HStack(spacing: 0) {
                    ForEach(fans.readings) { TemperatureMeter(reading: $0) }
                }
                .frame(maxHeight: .infinity)
                Label("This Mac cools itself silently, without fans.", systemImage: "wind")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var fanColumn: some View {
        switch fans.availability {
        case .checking:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .noFans:
            EmptyView()
        case .unsupported:
            VStack(alignment: .leading, spacing: 10) {
                ForEach(fans.fans) { FanRow(fan: $0, isEnabled: false) { _ in } }
                Text("Fan control isn't available on this Mac yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .needsHelper, .helperOutdated:
            VStack(alignment: .leading, spacing: 8) {
                Text(fans.availability == .needsHelper
                    ? "Fan control needs a small helper that runs in the background with administrator access."
                    : "The fan helper needs updating to match this version of NotchUtils.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(fans.fans) { FanRow(fan: $0, isEnabled: false) { _ in } }
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    CapsuleButton(
                        title: helperButtonTitle,
                        symbol: "lock.fill",
                        isProminent: true,
                        action: fans.installHelper
                    )
                    if fans.isExperimental { ExperimentalTag() }
                }
                if let error = fans.helperError {
                    Text(error).font(.system(size: 11)).foregroundStyle(.red)
                }
            }
        case .ready:
            controls
        }
    }

    private var helperButtonTitle: String {
        if fans.availability == .helperOutdated {
            return fans.isChangingHelper ? "Updating" : "Update Fan Helper"
        }
        return fans.isChangingHelper ? "Setting Up" : "Set Up Fan Control"
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 9) {
            FanModePicker(mode: fans.mode, onChange: fans.setMode)
            ForEach(fans.fans) { fan in
                FanRow(fan: fan, isEnabled: fan.isManual) { fans.setSpeed(fan: fan.id, rpm: $0) }
            }
            if fans.isExperimental { ExperimentalTag() }
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 6) {
                Text(noteText)
                    .font(.system(size: 11))
                    .foregroundStyle(fans.fallbackReason == nil ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if fans.mode == .automatic {
                    Button(action: fans.removeHelper) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .help("Remove the fan helper")
                    .accessibilityLabel("Remove the fan helper")
                }
            }
        }
    }

    private var noteText: String {
        switch fans.fallbackReason {
        case "hot": return "Back to automatic: the Mac is running hot."
        case "lease": return "Back to automatic: the app stopped responding."
        case "helper stopped": return "Back to automatic: the helper stopped."
        case "refused": return "macOS wouldn't give up control of the fans just now."
        case "system": return "Back to automatic: macOS took back control of the fans."
        default: break
        }
        if fans.isEngaging { return "Taking control of the fans. This can take a few seconds." }
        switch fans.mode {
        case .automatic: return "macOS is managing the fans."
        // The Experimental tag takes the second line these otherwise use.
        case .manual where fans.isExperimental, .max where fans.isExperimental:
            return "Returns to automatic if the Mac gets hot or the app stops."
        case .manual: return "Can't go below the automatic speed. Returns to automatic if the Mac gets hot or the app stops."
        case .max: return "Fans at full speed. Returns to automatic if the Mac gets hot or the app stops."
        }
    }
}

/// Fan control on this Mac rests on other people's research, not testing on this model.
struct ExperimentalTag: View {
    var body: some View {
        Label("Experimental on this Mac", systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.yellow)
            .help("Fan control hasn't been tested on this Mac model yet. Tell us how it goes on GitHub.")
    }
}

struct ThermalsNote: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TemperatureMeter: View {
    let reading: FanModel.Reading

    private var tint: Color {
        switch reading.celsius {
        case 95...: return .red
        case 85...: return .orange
        default: break
        }
        switch reading.name {
        case "CPU": return .blue
        case "GPU": return .purple
        case "SSD": return .orange
        case "Battery": return .green
        default: return .white
        }
    }

    var body: some View {
        Meter(
            title: reading.name,
            value: Double(reading.celsius) / 100,
            tint: tint,
            suffix: "°",
            spokenValue: "\(reading.celsius) degrees Celsius"
        )
    }
}

struct FanModePicker: View {
    let mode: FanModel.Mode
    let onChange: (FanModel.Mode) -> Void

    var body: some View {
        HStack(spacing: 0) {
            segment("Automatic", .automatic)
            segment("Manual", .manual)
            segment("Max", .max)
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.08)))
    }

    private func segment(_ title: String, _ value: FanModel.Mode) -> some View {
        Button { onChange(value) } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(mode == value ? .black : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(Capsule().fill(mode == value ? Color.white : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(mode == value ? .isSelected : [])
    }
}

struct FanRow: View {
    let fan: FanModel.Fan
    let isEnabled: Bool
    let onChange: (Double) -> Void

    private var lowerBound: Double {
        fan.isManual ? max(fan.floor, fan.minimum) : fan.minimum
    }

    var body: some View {
        VStack(spacing: 1) {
            HStack {
                Text(fan.name).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(fan.rpm).formatted()) rpm")
                    .fontWeight(.medium)
                    .monospacedDigit()
            }
            .font(.system(size: 12))
            CapsuleSlider(
                value: fan.isManual ? fan.target : fan.rpm,
                range: min(lowerBound, fan.maximum - 1)...fan.maximum,
                showsThumb: isEnabled,
                onChange: onChange
            )
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.35)
            .accessibilityLabel(fan.name)
        }
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
