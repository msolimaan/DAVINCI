import SwiftUI

/// Slowly drifting gradient "aurora" painted behind every module.
struct ModuleBackground: View {
    let palette: ModulePalette
    @State private var drift = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                palette.background
                Circle()
                    .fill(palette.glow.opacity(0.42))
                    .frame(width: size.width * 0.7, height: size.width * 0.7)
                    .blur(radius: 120)
                    .offset(
                        x: size.width * (drift ? 0.32 : 0.2),
                        y: -size.height * (drift ? 0.36 : 0.24)
                    )
                Circle()
                    .fill(palette.top.opacity(0.85))
                    .frame(width: size.width * 0.8, height: size.width * 0.8)
                    .blur(radius: 140)
                    .offset(
                        x: -size.width * (drift ? 0.36 : 0.24),
                        y: size.height * (drift ? 0.4 : 0.28)
                    )
                LinearGradient(colors: [.clear, .black.opacity(0.3)], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            DebugLog.write("ModuleBackground appeared")
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}

/// The big glassy illustration at the centre of each module's welcome screen.
struct HeroIcon: View {
    let symbol: String
    let palette: ModulePalette
    var size: CGFloat = 170
    @State private var floating = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        ZStack {
            Circle()
                .fill(palette.glow.opacity(0.4))
                .frame(width: size * 1.15, height: size * 1.15)
                .blur(radius: 44)
            shape
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.4), .white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.75), .white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.25), radius: 26, y: 18)
            Image(systemName: symbol)
                .font(.system(size: size * 0.44, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .shadow(color: palette.glow, radius: 18)
        }
        .rotation3DEffect(.degrees(floating ? 5 : -5), axis: (x: 1, y: 1, z: 0))
        .offset(y: floating ? -6 : 6)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                floating = true
            }
        }
        .accessibilityHidden(true)
    }
}

/// Small rounded-square module icon used in the sidebar and headers.
struct ModuleBadge: View {
    let module: Module
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(module.palette.iconFill)
            .overlay(
                Image(systemName: module.symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
            .shadow(color: module.palette.glow.opacity(0.45), radius: 3, y: 1)
    }
}

/// Circular progress used while scanning. Pass `nil` for an indeterminate spinner.
struct ProgressRing<Center: View>: View {
    var progress: Double?
    var palette: ModulePalette
    var diameter: CGFloat = 250
    var lineWidth: CGFloat = 14
    @ViewBuilder var center: () -> Center
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress.map { max(0.02, min(1, $0)) } ?? 0.3)
                .stroke(palette.ring, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .rotationEffect(.degrees(progress == nil && spin ? 360 : 0))
                .shadow(color: palette.glow.opacity(0.9), radius: 12)
                .animation(.easeInOut(duration: 0.4), value: progress)
            Circle()
                .fill(.white.opacity(0.06))
                .padding(lineWidth * 1.8)
            center()
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                spin = true
            }
        }
    }
}

/// A ring gauge for live stats (CPU, memory, disk).
struct GaugeRing: View {
    let fraction: Double
    let color: Color
    var diameter: CGFloat = 120
    var lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(
                    AngularGradient(colors: [color.opacity(0.6), color], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.7), radius: 6)
                .animation(.easeInOut(duration: 0.6), value: fraction)
        }
        .frame(width: diameter, height: diameter)
    }
}
