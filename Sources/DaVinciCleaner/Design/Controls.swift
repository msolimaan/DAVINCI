import AppKit
import CleanerCore
import SwiftUI

/// The round call-to-action button ("Scan", "Clean", "Run") that anchors every module.
struct ScanButton: View {
    let title: String
    let palette: ModulePalette
    var diameter: CGFloat = 110
    var isEnabled = true
    let action: () -> Void

    @State private var pulse = false
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.55), lineWidth: 2)
                    .scaleEffect(pulse && isEnabled ? 1.38 : 1)
                    .opacity(pulse && isEnabled ? 0 : 0.8)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.82)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: palette.glow.opacity(0.85), radius: hovering ? 30 : 18)
                Text(title)
                    .font(.system(size: diameter * 0.17, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.top)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 10)
            }
            .frame(width: diameter, height: diameter)
            .scaleEffect(hovering && isEnabled ? 1.05 : 1)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
        .onAppear {
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
        .accessibilityLabel(title)
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Capsule buttons: `.primary` is solid white with coloured text, `.secondary` is frosted glass.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }

    var kind: Kind = .secondary
    var tint: Color = .black

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, kind: kind, tint: tint)
    }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        let tint: Color
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .foregroundStyle(foreground)
                .background(Capsule().fill(fill))
                .overlay(Capsule().strokeBorder(.white.opacity(kind == .secondary ? 0.2 : 0)))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Capsule())
        }

        private var foreground: Color {
            switch kind {
            case .primary: return tint
            case .secondary, .destructive: return .white
            }
        }

        private var fill: Color {
            let pressed = configuration.isPressed
            switch kind {
            case .primary: return .white.opacity(pressed ? 0.85 : 1)
            case .secondary: return .white.opacity(pressed ? 0.26 : 0.14)
            case .destructive: return Theme.danger.opacity(pressed ? 0.7 : 0.85)
            }
        }
    }
}

/// Round checkbox in the CleanMyMac style.
struct CheckCircle: View {
    enum Mark: Equatable { case on, off, mixed }

    let mark: Mark
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.white.opacity(mark == .off ? 0.55 : 0), lineWidth: 1.5)
            if mark != .off {
                Circle().fill(.white)
                Image(systemName: mark == .on ? "checkmark" : "minus")
                    .font(.system(size: size * 0.52, weight: .heavy))
                    .foregroundStyle(.black.opacity(0.75))
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: mark)
    }
}

struct CheckButton: View {
    let mark: CheckCircle.Mark
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CheckCircle(mark: mark)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mark == .on ? "Selected" : "Not selected")
    }
}

extension CheckCircle.Mark {
    /// Mark for a group given how many of its items are selected.
    init(selected: Int, total: Int) {
        if selected == 0 || total == 0 {
            self = .off
        } else if selected == total {
            self = .on
        } else {
            self = .mixed
        }
    }
}

/// A glass panel used for grouped content.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Theme.cardFill))
            .overlay(shape.strokeBorder(Theme.cardStroke))
    }
}

/// A list row that highlights on hover and when selected.
struct HoverRow<Content: View>: View {
    var isSelected = false
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    var body: some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Theme.rowSelected : (hovering ? Theme.rowHover : Color.clear))
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

struct SearchField: View {
    @Binding var text: String
    var prompt = "Search"

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.secondaryText)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(.white.opacity(0.1)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.14)))
        .frame(maxWidth: 260)
    }
}

struct SizeText: View {
    let bytes: Int64
    var font: Font = .system(size: 13, weight: .semibold, design: .rounded)

    var body: some View {
        Text(ByteFormatter.string(bytes))
            .font(font)
            .monospacedDigit()
    }
}

/// A thin proportional bar used to compare sizes in lists.
struct SizeBar: View {
    let fraction: Double
    var color: Color = .white

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                Capsule()
                    .fill(color.opacity(0.85))
                    .frame(width: max(3, proxy.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 4)
    }
}

struct FileIcon: View {
    let url: URL
    var size: CGFloat = 28

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// A segmented control drawn to match the glass look.
struct GlassSegmentedPicker<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isSelected = option.value == selection
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .foregroundStyle(isSelected ? Color.black.opacity(0.8) : .white)
                        .background(Capsule().fill(isSelected ? Color.white : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(.white.opacity(0.12)))
    }
}

/// A compact filter menu drawn as a glass capsule.
struct FilterMenu<Value: Hashable>: View {
    let title: String
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title).foregroundStyle(Theme.secondaryText)
                Text(options.first { $0.value == selection }?.title ?? "")
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(0.12)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
