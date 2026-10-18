import SwiftUI

enum Theme {
    static let cyan = Color(red: 0.0, green: 0.79, blue: 1.0)      // Alexa light-ring cyan
    static let blue = Color(red: 0.12, green: 0.31, blue: 1.0)
    static let violet = Color(red: 0.55, green: 0.42, blue: 1.0)
    static let amber = Color(red: 1.0, green: 0.68, blue: 0.2)
    static let alert = Color(red: 1.0, green: 0.42, blue: 0.25)
    static let background = Color(red: 0.03, green: 0.04, blue: 0.07)
    static let card = Color.white.opacity(0.055)
    static let stroke = Color.white.opacity(0.08)
    static let ring = LinearGradient(colors: [cyan, blue], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// A rendered Echo Dot (sphere, fabric, top buttons, LED clock) with its light ring.
struct EchoDotView<Display: View>: View {
    var ringColors: [Color]
    var ringStrength: Double         // 0…1
    var spin: Angle = .zero          // rotates the ring gradient while Alexa is "thinking"
    @ViewBuilder var display: Display

    private let size: CGFloat = 156

    var body: some View {
        ZStack {
            // Glow the ring throws on the "table".
            Ellipse()
                .fill(ringColors.first!.opacity(0.55 * ringStrength))
                .frame(width: size * 1.1, height: 34)
                .blur(radius: 22)
                .offset(y: size * 0.5)

            // Sphere.
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.33), Color(white: 0.15), Color(white: 0.05)],
                                     center: UnitPoint(x: 0.36, y: 0.24), startRadius: 4, endRadius: size * 0.72))
                .overlay(FabricTexture().clipShape(Circle()).opacity(0.5))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .clear],
                                                              startPoint: .top, endPoint: .center), lineWidth: 1))
                .shadow(color: .black.opacity(0.7), radius: 16, y: 14)
                .frame(width: size, height: size)

            // Top buttons: volume down, action, volume up.
            HStack(spacing: 16) {
                Image(systemName: "minus")
                Circle().stroke(lineWidth: 1.4).frame(width: 7, height: 7)
                Image(systemName: "plus")
            }
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white.opacity(0.22))
            .offset(y: -size * 0.36)

            // LED display.
            display
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .white.opacity(0.55), radius: 6)
                .offset(y: -2)

            // Light ring around the base: the front (lower) half of an ellipse on the sphere's lower edge.
            let ring = AngularGradient(colors: ringColors + [ringColors.first!], center: .center, angle: spin)
            let ringShape = Ellipse().trim(from: 0, to: 0.5)
            ringShape
                .stroke(ring, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .blur(radius: 7)
                .opacity(ringStrength)
                .frame(width: size * 0.74, height: 22)
                .offset(y: size * 0.33)
            ringShape
                .stroke(ring, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .opacity(0.25 + 0.75 * ringStrength)
                .frame(width: size * 0.74, height: 22)
                .offset(y: size * 0.33)
        }
        .frame(width: size, height: size + 30)
        .accessibilityElement(children: .combine)
    }
}

/// Speaker-cloth speckle, drawn once from a fixed seed.
private struct FabricTexture: View {
    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 33) / Double(1 << 31)
            }
            for _ in 0..<1800 {
                let rect = CGRect(x: next() * size.width, y: next() * size.height, width: 1.1, height: 1.1)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.05 + next() * 0.09)))
            }
        }
    }
}
