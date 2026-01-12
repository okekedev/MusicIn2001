import SwiftUI

// MARK: - Theme Manager (Observable)
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    // Primary (H, S, B)
    @Published var primaryH: Double { didSet { save("primaryH", primaryH) } }
    @Published var primaryS: Double { didSet { save("primaryS", primaryS) } }
    @Published var primaryB: Double { didSet { save("primaryB", primaryB) } }

    // Accent (H, S, B)
    @Published var accentH: Double { didSet { save("accentH", accentH) } }
    @Published var accentS: Double { didSet { save("accentS", accentS) } }
    @Published var accentB: Double { didSet { save("accentB", accentB) } }

    // Background (H, S, B)
    @Published var bgH: Double { didSet { save("bgH", bgH) } }
    @Published var bgS: Double { didSet { save("bgS", bgS) } }
    @Published var bgB: Double { didSet { save("bgB", bgB) } }

    // Text (H, S, B)
    @Published var textH: Double { didSet { save("textH", textH) } }
    @Published var textS: Double { didSet { save("textS", textS) } }
    @Published var textB: Double { didSet { save("textB", textB) } }

    private func save(_ key: String, _ value: Double) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private static func load(_ key: String, _ defaultValue: Double) -> Double {
        UserDefaults.standard.object(forKey: key) as? Double ?? defaultValue
    }

    private init() {
        // Primary: Windows Media Player Blue
        self.primaryH = Self.load("primaryH", 0.58)
        self.primaryS = Self.load("primaryS", 1.0)
        self.primaryB = Self.load("primaryB", 0.83)
        // Accent: WMP Orange
        self.accentH = Self.load("accentH", 0.07)
        self.accentS = Self.load("accentS", 1.0)
        self.accentB = Self.load("accentB", 1.0)
        // Background: Dark Navy Blue
        self.bgH = Self.load("bgH", 0.6)
        self.bgS = Self.load("bgS", 0.35)
        self.bgB = Self.load("bgB", 0.10)
        // Text: Near white
        self.textH = Self.load("textH", 0.0)
        self.textS = Self.load("textS", 0.0)
        self.textB = Self.load("textB", 0.95)
    }

    func resetToDefaults() {
        primaryH = 0.58; primaryS = 1.0; primaryB = 0.83
        accentH = 0.07; accentS = 1.0; accentB = 1.0
        bgH = 0.6; bgS = 0.35; bgB = 0.10
        textH = 0.0; textS = 0.0; textB = 0.95
    }

    // MARK: - Computed Colors

    var primary: Color { Color(hue: primaryH, saturation: primaryS, brightness: primaryB) }
    var accent: Color { Color(hue: accentH, saturation: accentS, brightness: accentB) }

    // Backgrounds - base + lighter variations
    var background: Color { Color(hue: bgH, saturation: bgS, brightness: bgB) }
    var cardBackground: Color { Color(hue: bgH, saturation: max(0, bgS - 0.02), brightness: min(1, bgB + 0.06)) }
    var elevatedBackground: Color { Color(hue: bgH, saturation: max(0, bgS - 0.04), brightness: min(1, bgB + 0.10)) }

    // Text - base + dimmer variations
    var textPrimary: Color { Color(hue: textH, saturation: textS, brightness: textB) }
    var textSecondary: Color { Color(hue: textH, saturation: textS, brightness: textB * 0.6) }
    var textTertiary: Color { Color(hue: textH, saturation: textS, brightness: textB * 0.4) }
}

struct Music2001Theme {
    private static var tm: ThemeManager { ThemeManager.shared }

    static var primary: Color { tm.primary }
    static var accent: Color { tm.accent }
    static var background: Color { tm.background }
    static var cardBackground: Color { tm.cardBackground }
    static var elevatedBackground: Color { tm.elevatedBackground }
    static var textPrimary: Color { tm.textPrimary }
    static var textSecondary: Color { tm.textSecondary }
    static var textTertiary: Color { tm.textTertiary }
    static let error = Color(red: 239/255, green: 68/255, blue: 68/255)

    static var primaryGradient: LinearGradient {
        LinearGradient(colors: [primary, primary.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Sizing
    static let cornerRadius: CGFloat = 16
    static let smallCornerRadius: CGFloat = 10
    static let smallSpacing: CGFloat = 8
    static let spacing: CGFloat = 16
    static let largeSpacing: CGFloat = 24

    // Shadows
    static let shadowColor = Color.black.opacity(0.4)
    static let shadowRadius: CGFloat = 12
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(
                Group {
                    if isDisabled {
                        Color.gray.opacity(0.3)
                    } else {
                        Music2001Theme.primaryGradient
                    }
                }
            )
            .cornerRadius(Music2001Theme.smallCornerRadius)
            .shadow(color: isDisabled ? .clear : Music2001Theme.primary.opacity(0.4), radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundColor(Music2001Theme.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Music2001Theme.primary.opacity(0.1))
            .cornerRadius(Music2001Theme.smallCornerRadius)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundColor(Music2001Theme.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: Music2001Theme.smallCornerRadius)
                    .stroke(Music2001Theme.textTertiary, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Card Style

struct CardStyle: ViewModifier {
    var padding: CGFloat = Music2001Theme.spacing

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Music2001Theme.cardBackground)
            .cornerRadius(Music2001Theme.cornerRadius)
            .shadow(color: Music2001Theme.shadowColor, radius: Music2001Theme.shadowRadius, y: 4)
    }
}

extension View {
    func cardStyle(padding: CGFloat = Music2001Theme.spacing) -> some View {
        modifier(CardStyle(padding: padding))
    }
}

// MARK: - Animated Progress Ring

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 8
    var size: CGFloat = 120

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Music2001Theme.primary.opacity(0.2), lineWidth: lineWidth)

            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Music2001Theme.primaryGradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: progress)

            // Percentage text
            VStack(spacing: 4) {
                Text("\(Int(progress * 100))")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(Music2001Theme.textPrimary)
                Text("%")
                    .font(.caption)
                    .foregroundColor(Music2001Theme.textSecondary)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Waveform Animation

struct WaveformView: View {
    @State private var animating = false
    let barCount = 5

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Music2001Theme.primaryGradient)
                    .frame(width: 4, height: animating ? CGFloat.random(in: 15...35) : 15)
                    .animation(
                        .easeInOut(duration: 0.4)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.1),
                        value: animating
                    )
            }
        }
        .frame(height: 40)
        .onAppear { animating = true }
    }
}

// MARK: - Drop Zone

struct DropZoneView: View {
    let icon: String
    let title: String
    let subtitle: String
    var isTargeted: Bool = false
    var hasContent: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Music2001Theme.primary.opacity(0.1))
                    .frame(width: 72, height: 72)

                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(Music2001Theme.primary)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(Music2001Theme.textPrimary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(Music2001Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(
            RoundedRectangle(cornerRadius: Music2001Theme.cornerRadius)
                .strokeBorder(
                    isTargeted ? Music2001Theme.primary : Music2001Theme.textTertiary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: hasContent ? [] : [10])
                )
                .background(
                    RoundedRectangle(cornerRadius: Music2001Theme.cornerRadius)
                        .fill(isTargeted ? Music2001Theme.primary.opacity(0.05) : Color.clear)
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isTargeted)
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundColor(Music2001Theme.textPrimary)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(Music2001Theme.textSecondary)
            }
        }
    }
}

// MARK: - Theme Editor View

struct ThemeEditorView: View {
    @ObservedObject var themeManager = ThemeManager.shared
    @Binding var isShowing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Theme")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(themeManager.textPrimary)
                Spacer()
                Button {
                    themeManager.resetToDefaults()
                } label: {
                    Text("Reset")
                        .font(.caption)
                        .foregroundColor(themeManager.accent)
                }
                .buttonStyle(.plain)

                Button {
                    isShowing = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(themeManager.textSecondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(spacing: 16) {
                    // Primary
                    HSBSliderGroup(
                        title: "Primary",
                        color: themeManager.primary,
                        hue: $themeManager.primaryH,
                        saturation: $themeManager.primaryS,
                        brightness: $themeManager.primaryB,
                        tm: themeManager
                    )

                    // Accent
                    HSBSliderGroup(
                        title: "Accent",
                        color: themeManager.accent,
                        hue: $themeManager.accentH,
                        saturation: $themeManager.accentS,
                        brightness: $themeManager.accentB,
                        tm: themeManager
                    )

                    // Background
                    HSBSliderGroup(
                        title: "Background",
                        color: themeManager.background,
                        hue: $themeManager.bgH,
                        saturation: $themeManager.bgS,
                        brightness: $themeManager.bgB,
                        tm: themeManager
                    )

                    // Text
                    HSBSliderGroup(
                        title: "Text",
                        color: themeManager.textPrimary,
                        hue: $themeManager.textH,
                        saturation: $themeManager.textS,
                        brightness: $themeManager.textB,
                        tm: themeManager
                    )
                }
            }
        }
        .padding(12)
        .frame(width: 220)
        .background(themeManager.cardBackground)
    }
}

// MARK: - HSB Slider Group (Color, Vivid, Bright)

struct HSBSliderGroup: View {
    let title: String
    let color: Color
    @Binding var hue: Double
    @Binding var saturation: Double
    @Binding var brightness: Double
    @ObservedObject var tm: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title with color preview
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundColor(tm.textPrimary)
            }

            VStack(spacing: 4) {
                // Hue (Color)
                SliderRow(
                    label: "Color",
                    value: $hue,
                    tm: tm,
                    colors: (0...10).map { Color(hue: Double($0) / 10, saturation: 0.8, brightness: 0.9) }
                )

                // Saturation (Vivid)
                SliderRow(
                    label: "Vivid",
                    value: $saturation,
                    tm: tm,
                    colors: [Color(hue: hue, saturation: 0, brightness: 0.7), Color(hue: hue, saturation: 1, brightness: 0.9)]
                )

                // Brightness (Bright)
                SliderRow(
                    label: "Bright",
                    value: $brightness,
                    tm: tm,
                    colors: [Color(hue: hue, saturation: saturation, brightness: 0), Color(hue: hue, saturation: saturation, brightness: 1)]
                )
            }
        }
        .padding(8)
        .background(tm.background.opacity(0.5))
        .cornerRadius(6)
    }
}

struct SliderRow: View {
    let label: String
    @Binding var value: Double
    @ObservedObject var tm: ThemeManager
    let colors: [Color]

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundColor(tm.textSecondary)
                .frame(width: 32, alignment: .leading)

            ZStack(alignment: .leading) {
                LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                    .frame(height: 10)
                    .cornerRadius(5)

                GeometryReader { geo in
                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .shadow(color: .black.opacity(0.3), radius: 1)
                        .offset(x: value * (geo.size.width - 12))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in
                                    value = min(max(v.location.x / geo.size.width, 0), 1)
                                }
                        )
                }
                .frame(height: 12)
            }
        }
    }
}
