import SwiftUI


struct GlowButton: View {
    let title: String
    let icon: String
    var tint: [Color] = [Theme.cyan, Theme.blue]
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Capsule().fill(LinearGradient(colors: tint, startPoint: .leading, endPoint: .trailing)))
                .shadow(color: tint[0].opacity(isEnabled ? 0.55 : 0), radius: 10, y: 2)
                .opacity(isEnabled ? 1 : 0.35)
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}


struct CardField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .onSubmit(onSubmit)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke))
    }
}


struct CapsulePicker<Value: Hashable>: View {
    let options: [(value: Value, title: String, icon: String?)]
    @Binding var selection: Value
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let selected = selection == option.value
                Button {
                    withAnimation(.spring(duration: 0.3)) { selection = option.value }
                } label: {
                    Group {
                        if let icon = option.icon { Label(option.title, systemImage: icon) } else { Text(option.title) }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? .white : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background {
                        if selected { Capsule().fill(Theme.ring).matchedGeometryEffect(id: "pick", in: ns) }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.card))
        .overlay(Capsule().strokeBorder(Theme.stroke))
    }
}


struct DayStrip: View {
    @Binding var selection: Int  // days from today, 0...6
    var isDisabled: (Int) -> Bool = { _ in false }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                let date = Calendar.current.date(byAdding: .day, value: i, to: .now)!
                let selected = selection == i
                Button {
                    withAnimation(.spring(duration: 0.25)) { selection = i }
                } label: {
                    VStack(spacing: 1) {
                        Text(i == 0 ? "Today" : i == 1 ? "Tmrw" : date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.system(size: 9, weight: .semibold))
                        Text(date.formatted(.dateTime.day()))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(selected ? .white : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(selected ? AnyShapeStyle(Theme.ring) : AnyShapeStyle(Theme.card)))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(isDisabled(i))
                .opacity(isDisabled(i) ? 0.3 : 1)
                .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
            }
        }
    }
}


struct TimerDial: View {
    @Binding var minutes: Int
    static let maxMinutes = 120

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = side / 2 - 6
            let fraction = Double(minutes) / Double(Self.maxMinutes)
            ZStack {
                Circle().stroke(Theme.card, lineWidth: 12).padding(6)
                // 5-minute ticks.
                ForEach(0..<24) { i in
                    Capsule()
                        .fill(.white.opacity(i % 3 == 0 ? 0.35 : 0.14))
                        .frame(width: 1.5, height: i % 3 == 0 ? 7 : 4)
                        .offset(y: -radius + 14)
                        .rotationEffect(.degrees(Double(i) * 15))
                }
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(AngularGradient(colors: [Theme.blue, Theme.cyan], center: .center,
                                            startAngle: .zero, endAngle: .degrees(360 * fraction)),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(6)
                    .shadow(color: Theme.cyan.opacity(0.6), radius: 8)
                Circle()
                    .fill(.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: Theme.cyan, radius: 6)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(360 * fraction))
                VStack(spacing: 0) {
                    Text("\(minutes)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "minutes")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: side, height: side)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let dx = value.location.x - side / 2, dy = value.location.y - side / 2
                var angle = atan2(dx, -dy) * 180 / .pi
                if angle < 0 { angle += 360 }
                var m = Int((angle / 360 * Double(Self.maxMinutes)).rounded())
                // Don't wrap past the top: stay pinned at the end the finger came from.
                if minutes > Self.maxMinutes * 3 / 4 && m < Self.maxMinutes / 4 { m = Self.maxMinutes }
                if minutes < Self.maxMinutes / 4 && m > Self.maxMinutes * 3 / 4 { m = 1 }
                minutes = min(Self.maxMinutes, max(1, m))
            })
            .accessibilityElement()
            .accessibilityLabel("Timer length")
            .accessibilityValue("\(minutes) minutes")
            .accessibilityAdjustableAction { direction in
                minutes = min(Self.maxMinutes, max(1, minutes + (direction == .increment ? 1 : -1)))
            }
        }
    }
}


struct PresetButton: View {
    let minutes: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Theme.card)
                Circle()
                    .trim(from: 0, to: min(1, Double(minutes) / 60))
                    .stroke(Theme.ring, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(4)
                VStack(spacing: -2) {
                    Text("\(minutes)").font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("min").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 54, height: 54)
            .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .help("Start a \(minutes)-minute timer now")
    }
}

/// Hour : minute with chevrons (and vertical drag on the digits), plus AM/PM.
struct TimeWheel: View {
    @Binding var hour: Int     // 1…12
    @Binding var minute: Int   // 0…59
    @Binding var pm: Int       // 0 = AM, 1 = PM

    var body: some View {
        HStack(spacing: 6) {
            DigitColumn(value: $hour, range: 1...12, step: 1, format: "%d")
            Text(":").font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(.secondary).offset(y: -3)
            DigitColumn(value: $minute, range: 0...59, step: 5, format: "%02d")
            VStack(spacing: 4) {
                ForEach(["AM", "PM"].indices, id: \.self) { i in
                    Button {
                        withAnimation(.spring(duration: 0.25)) { pm = i }
                    } label: {
                        Text(i == 0 ? "AM" : "PM")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(pm == i ? .white : .secondary)
                            .frame(width: 40, height: 26)
                            .background(Capsule().fill(pm == i ? AnyShapeStyle(Theme.ring) : AnyShapeStyle(Theme.card)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.stroke))
    }
}

private struct DigitColumn: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int          // chevron step; drag moves by 1
    let format: String
    @State private var dragStart: Int?

    private func wrap(_ v: Int) -> Int {
        let span = range.count
        return ((v - range.lowerBound) % span + span) % span + range.lowerBound
    }

    var body: some View {
        VStack(spacing: 0) {
            chevron("chevron.up") { value = wrap((value / step) * step + step) }
            Text(String(format: format, value))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(width: 64)
                .contentShape(Rectangle())
                .gesture(DragGesture().onChanged { g in
                    let start = dragStart ?? value
                    dragStart = start
                    value = wrap(start - Int(g.translation.height / 8))
                }.onEnded { _ in dragStart = nil })
                .accessibilityAdjustableAction { d in value = wrap(value + (d == .increment ? 1 : -1)) }
            chevron("chevron.down") { value = wrap(value % step == 0 ? value - step : (value / step) * step) }
        }
    }

    private func chevron(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            Image(systemName: name)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
