import AppKit
import SwiftUI

struct PanelView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = AlertKind.timer

    var body: some View {
        VStack(spacing: 0) {
            Hero()
            if model.isSignedIn {
                VStack(spacing: 14) {
                    TabSwitcher(tab: $tab)
                    switch tab {
                    case .timer: TimerControls()
                    case .alarm: ScheduleControls(kind: .alarm)
                    case .reminder: ScheduleControls(kind: .reminder)
                    }
                    UpcomingList()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .frame(width: 340)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Hero: the glowing Echo Dot

private struct Hero: View {
    @Environment(AppModel.self) private var model

    private var ringColors: [Color] {
        switch model.phase {
        case .failure: [Theme.alert, .orange]
        case .success: [Theme.cyan, .white]
        default: [Theme.cyan, Theme.blue]
        }
    }

    private var strength: Double {
        guard model.isSignedIn else { return 0.15 }
        switch model.phase {
        case .idle: return model.nextTimer == nil ? 0.35 : 0.75
        case .sending, .success, .failure: return 1
        }
    }

    var body: some View {
        TimelineView(.animation(paused: model.phase != .sending)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let sending = model.phase == .sending
            let pulse = sending ? 0.75 + 0.25 * sin(t * 4) : 1
            ZStack(alignment: .top) {
                // Glow from the top of the panel.
                RadialGradient(colors: [ringColors[0].opacity(0.55 * strength * pulse),
                                        ringColors[1].opacity(0.25 * strength * pulse), .clear],
                               center: .top, startRadius: 0, endRadius: 260)
                Ellipse()
                    .fill(ringColors[0].opacity(0.45 * strength * pulse))
                    .frame(width: 280, height: 110)
                    .blur(radius: 55)
                    .offset(y: -70)

                VStack(spacing: 6) {
                    TopBar()
                    EchoDotView(ringColors: ringColors, ringStrength: strength * pulse,
                                spin: .degrees(sending ? t * 220 : 0)) {
                        LEDDisplay()
                    }
                    .padding(.top, 2)
                    StatusLine()
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
            .animation(.easeInOut(duration: 0.6), value: model.phase)
        }
    }
}

private struct LEDDisplay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.isSignedIn {
            Text("--:--").opacity(0.4)
        } else if let fire = model.nextTimer?.fireDate {
            Text(timerInterval: Date.now...max(fire, .now), countsDown: true)
        } else {
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
            }
        }
    }
}

private struct TopBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            if model.isSignedIn {
                Menu {
                    ForEach(model.devices) { device in
                        Button {
                            model.selectedDeviceID = device.id
                        } label: {
                            Text(device.isOnline ? device.name : "\(device.name) (offline)")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(model.selectedDevice?.isOnline == true ? Color.green : Color.gray)
                            .frame(width: 7, height: 7)
                        Text(model.selectedDevice?.name ?? "Finding your Echo…")
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.black.opacity(0.35)))
                    .overlay(Capsule().strokeBorder(Theme.stroke))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            } else {
                Text("AlexaAssist").font(.system(size: 13, weight: .semibold))
            }
            Spacer()
            Menu {
                Button("Settings…") { model.openSettings() }
                if model.isSignedIn { Button("Sign Out") { model.signOut() } }
                Divider()
                Button("Quit AlexaAssist") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.black.opacity(0.35)))
                    .overlay(Circle().strokeBorder(Theme.stroke))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

private struct StatusLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.isSignedIn {
            VStack(spacing: 8) {
                if let banner = model.banner { Text(banner.text).font(.caption).foregroundStyle(Theme.alert) }
                Text("Sign in with the Amazon account your Echo uses.\nYour Amazon site is detected automatically.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                GlowButton(title: "Sign in with Amazon", icon: "person.crop.circle") { model.openSignIn() }
                    .frame(width: 220)
            }
        } else if let banner = model.banner {
            HStack(spacing: 8) {
                Image(systemName: banner.isError ? "exclamationmark.triangle.fill"
                      : model.phase == .sending ? "waveform" : "checkmark.circle.fill")
                    .foregroundStyle(banner.isError ? Theme.alert : Theme.cyan)
                    .symbolEffect(.variableColor.iterative, isActive: model.phase == .sending)
                Text(banner.text)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
                    .textSelection(.enabled)
                if banner.canRetry {
                    Button("Retry") { Task { await model.retry() } }.buttonStyle(.link).font(.system(size: 11, weight: .semibold))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(.black.opacity(0.4)))
            .transition(.opacity)
        } else {
            Text(model.nextTimer.map { "\($0.label?.capitalized ?? "Timer") running" } ?? "Ready")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Tabs

private struct TabSwitcher: View {
    @Binding var tab: AlertKind
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach([AlertKind.timer, .alarm, .reminder], id: \.self) { kind in
                Button {
                    withAnimation(.spring(duration: 0.3)) { tab = kind }
                } label: {
                    Label(kind.rawValue.capitalized, systemImage: kind.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tab == kind ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if tab == kind { Capsule().fill(Theme.ring).matchedGeometryEffect(id: "tab", in: ns) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.card))
        .overlay(Capsule().strokeBorder(Theme.stroke))
    }
}

extension AlertKind {
    var icon: String {
        switch self {
        case .timer: "timer"
        case .alarm: "alarm.fill"
        case .reminder: "bell.fill"
        }
    }

    var tint: Color {
        switch self {
        case .timer: Theme.cyan
        case .alarm: Theme.violet
        case .reminder: Theme.amber
        }
    }
}

// MARK: - Timer

private struct TimerControls: View {
    @Environment(AppModel.self) private var model
    @State private var minutes = 25
    @State private var label = ""

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                TimerDial(minutes: $minutes).frame(width: 156, height: 156)
                VStack(spacing: 8) {
                    Text("QUICK START").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                    Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                        GridRow { preset(1); preset(5) }
                        GridRow { preset(10); preset(25) }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            CardField(icon: "tag", placeholder: "Label (optional), e.g. focus", text: $label) { start(minutes, label) }
            GlowButton(title: "Start timer", icon: "play.fill") { start(minutes, label) }
                .disabled(model.phase == .sending)
        }
    }

    private func preset(_ m: Int) -> some View {
        PresetButton(minutes: m) { start(m, "") }.disabled(model.phase == .sending)
    }

    private func start(_ m: Int, _ label: String) {
        Task { await model.run(.timer(minutes: m, label: label)) }
    }
}

// MARK: - Alarm / reminder

private struct ScheduleControls: View {
    @Environment(AppModel.self) private var model
    let kind: AlertKind
    @State private var hour: Int
    @State private var minute = 0
    @State private var pm: Int
    @State private var day = 0  // days from today
    @State private var text = ""
    @State private var now = Date.now

    init(kind: AlertKind) {
        self.kind = kind
        _hour = State(initialValue: kind == .alarm ? 7 : 6)
        _pm = State(initialValue: kind == .alarm ? 0 : 1)
    }

    private func date(onDay day: Int) -> Date? {
        let cal = Calendar.current
        guard let d = cal.date(byAdding: .day, value: day, to: now) else { return nil }
        return cal.date(bySettingHour: hour % 12 + (pm == 1 ? 12 : 0), minute: minute, second: 0, of: d)
    }

    /// The picked time is already over (or under a minute away) today.
    private var passedToday: Bool { (date(onDay: 0) ?? .distantPast) <= now.addingTimeInterval(60) }

    private var trimmed: String { text.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 12) {
            if kind == .reminder {
                CardField(icon: "text.bubble", placeholder: "Remind me to… e.g. call mom", text: $text, onSubmit: submit)
            }
            TimeWheel(hour: $hour, minute: $minute, pm: $pm)
            DayStrip(selection: $day) { $0 == 0 && passedToday }
            if passedToday {
                Text("That time has passed today, so pick another day.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            GlowButton(title: kind == .alarm ? "Set alarm" : "Set reminder", icon: kind.icon,
                       tint: kind == .alarm ? [Theme.violet, Theme.blue] : [Theme.amber, Theme.alert],
                       action: submit)
                .disabled(model.phase == .sending || (kind == .reminder && trimmed.isEmpty))
        }
        .onChange(of: hour) { skipPastToday() }
        .onChange(of: minute) { skipPastToday() }
        .onChange(of: pm) { skipPastToday() }
        .task {
            // Keep "now" current while the panel is open.
            while !Task.isCancelled {
                now = .now
                skipPastToday()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    private func skipPastToday() {
        if day == 0 && passedToday { withAnimation { day = 1 } }
    }

    private func submit() {
        now = .now
        skipPastToday()
        guard let date = date(onDay: day), date > .now, kind == .alarm || !trimmed.isEmpty else { return }
        Task {
            await model.run(kind == .alarm ? .alarm(date) : .reminder(trimmed, date))
            if model.phase == .success { text = "" }
        }
    }
}

// MARK: - Upcoming

private struct UpcomingList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("UPCOMING").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                Spacer()
                if !model.alerts.isEmpty {
                    Text("\(model.alerts.count)").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                }
            }
            if model.alerts.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "moon.zzz.fill").foregroundStyle(.secondary)
                    Text("Nothing scheduled on Alexa").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.alerts) { AlertCard(alert: $0) }
                    }
                }
                .scrollIndicators(.never)
                .frame(height: min(CGFloat(model.alerts.count) * 58, 200))
            }
        }
    }
}

private struct AlertCard: View {
    @Environment(AppModel.self) private var model
    let alert: Alert

    var body: some View {
        HStack(spacing: 10) {
            badge
            VStack(alignment: .leading, spacing: 1) {
                Text(alert.label?.capitalized ?? alert.kind.rawValue.capitalized)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            trailing
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Button {
                Task { await model.cancel(alert) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.card))
            }
            .buttonStyle(PressStyle())
            .help("Cancel on Alexa")
            .accessibilityLabel("Cancel")
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.stroke))
    }

    @ViewBuilder private var badge: some View {
        let tint = alert.kind.tint
        ZStack {
            Circle().fill(tint.opacity(0.15))
            if alert.kind == .timer, let fire = alert.fireDate, let total = model.timerDurations[alert.id] {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Circle()
                        .trim(from: 0, to: max(0, min(1, fire.timeIntervalSinceNow / total)))
                        .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(2)
                }
            }
            Image(systemName: alert.kind.icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
        }
        .frame(width: 34, height: 34)
    }

    private var subtitle: String {
        let device = model.devices.first { $0.id == alert.deviceID }?.name ?? "Echo"
        guard alert.kind != .timer, let fire = alert.fireDate else { return device }
        let cal = Calendar.current
        let day = alert.repeats ? "Repeats"
            : cal.isDateInToday(fire) ? "Today"
            : cal.isDateInTomorrow(fire) ? "Tomorrow"
            : fire.formatted(.dateTime.weekday(.wide))
        return "\(day) · \(device)"
    }

    @ViewBuilder private var trailing: some View {
        if let fire = alert.fireDate {
            if alert.kind == .timer {
                Text(timerInterval: Date.now...max(fire, .now), countsDown: true).foregroundStyle(alert.kind.tint)
            } else {
                Text(fire, format: .dateTime.hour().minute())
            }
        }
    }
}
