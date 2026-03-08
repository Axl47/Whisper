import SwiftUI

enum OverlayInsetSurfaceTone {
    case command
    case content
    case footer
}

struct OverlayGlassContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 18) {
                content
            }
        } else {
            content
        }
    }
}

struct OverlayOuterSurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(
                OverlaySurfaceModifier(
                    kind: .outer,
                    colorScheme: colorScheme,
                    cornerRadius: 30
                )
            )
    }
}

struct OverlayInsetSurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let tone: OverlayInsetSurfaceTone
    let cornerRadius: CGFloat
    @ViewBuilder var content: Content

    init(
        tone: OverlayInsetSurfaceTone,
        cornerRadius: CGFloat = 24,
        @ViewBuilder content: () -> Content
    ) {
        self.tone = tone
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .modifier(
                OverlaySurfaceModifier(
                    kind: .inset(tone),
                    colorScheme: colorScheme,
                    cornerRadius: cornerRadius
                )
            )
    }
}

private enum OverlaySurfaceKind: Equatable {
    case outer
    case inset(OverlayInsetSurfaceTone)
}

private struct OverlaySurfaceModifier: ViewModifier {
    let kind: OverlaySurfaceKind
    let colorScheme: ColorScheme
    let cornerRadius: CGFloat

    private var fillColor: Color {
        switch kind {
        case .outer:
            return colorScheme == .dark
                ? Color.white.opacity(0.08)
                : Color.white.opacity(0.24)
        case .inset(.command):
            return colorScheme == .dark
                ? Color.white.opacity(0.10)
                : Color.white.opacity(0.26)
        case .inset(.content):
            return colorScheme == .dark
                ? Color.white.opacity(0.05)
                : Color.white.opacity(0.18)
        case .inset(.footer):
            return colorScheme == .dark
                ? Color.white.opacity(0.07)
                : Color.white.opacity(0.20)
        }
    }

    private var fallbackMaterial: Material {
        switch kind {
        case .outer:
            return .ultraThinMaterial
        case .inset:
            return .regularMaterial
        }
    }

    private var strokeColor: Color {
        switch kind {
        case .outer:
            return colorScheme == .dark
                ? Color.white.opacity(0.18)
                : Color.white.opacity(0.38)
        case .inset(.command):
            return colorScheme == .dark
                ? Color.white.opacity(0.14)
                : Color.white.opacity(0.28)
        case .inset(.content):
            return colorScheme == .dark
                ? Color.white.opacity(0.10)
                : Color.white.opacity(0.18)
        case .inset(.footer):
            return colorScheme == .dark
                ? Color.white.opacity(0.12)
                : Color.white.opacity(0.22)
        }
    }

    private var topHighlight: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.white.opacity(0.14)
    }

    private var washGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.04 : 0.10),
                Color.clear,
                Color.white.opacity(colorScheme == .dark ? 0.02 : 0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(washGradient)
                }
                .glassEffect(.regular.tint(fillColor), in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(strokeColor, lineWidth: kind == .outer ? 0.8 : 0.6)
                }
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(topHighlight)
                        .frame(height: 0.9)
                        .padding(.horizontal, 18)
                        .padding(.top, 1)
                }
                .shadow(
                    color: Color.black.opacity(kind == .outer ? 0.16 : 0.08),
                    radius: kind == .outer ? 22 : 12,
                    x: 0,
                    y: kind == .outer ? 12 : 6
                )
        } else {
            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(fillColor)
                        .background {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(fallbackMaterial)
                        }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(washGradient)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(strokeColor, lineWidth: kind == .outer ? 0.8 : 0.6)
                }
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(topHighlight)
                        .frame(height: 0.9)
                        .padding(.horizontal, 18)
                        .padding(.top, 1)
                }
                .shadow(
                    color: Color.black.opacity(kind == .outer ? 0.16 : 0.08),
                    radius: kind == .outer ? 18 : 10,
                    x: 0,
                    y: kind == .outer ? 10 : 5
                )
        }
    }
}
