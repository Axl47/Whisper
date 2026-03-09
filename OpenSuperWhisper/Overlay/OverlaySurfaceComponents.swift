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
            GlassEffectContainer(spacing: 12) {
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
                OverlayOuterSurfaceModifier(
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
                OverlayInsetSurfaceModifier(
                    tone: tone,
                    colorScheme: colorScheme,
                    cornerRadius: cornerRadius
                )
            )
    }
}

private struct OverlayOuterSurfaceModifier: ViewModifier {
    let colorScheme: ColorScheme
    let cornerRadius: CGFloat

    private var outerGlassTint: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.07)
            : Color.white.opacity(0.20)
    }

    private var fallbackFillColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.07)
            : Color.white.opacity(0.30)
    }

    private var highlightStrokeColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.24)
            : Color.white.opacity(0.38)
    }

    private var shadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.26)
            : Color.black.opacity(0.14)
    }

    private var outerBloomColor: Color {
        Color.white.opacity(colorScheme == .dark ? 0.07 : 0.14)
    }

    private var lowerLiftColor: Color {
        Color.white.opacity(colorScheme == .dark ? 0.015 : 0.04)
    }

    @ViewBuilder
    private func ambientWash(cornerRadius: CGFloat) -> some View {
        ZStack {
            RadialGradient(
                colors: [
                    outerBloomColor,
                    outerBloomColor.opacity(0.45),
                    Color.clear
                ],
                center: .top,
                startRadius: 0,
                endRadius: 460
            )

            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.018 : 0.05),
                    Color.clear,
                    lowerLiftColor
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var topHighlight: some View {
        Capsule()
            .fill(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.16))
            .frame(height: 1)
            .padding(.horizontal, 18)
            .padding(.top, 2)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background {
                    ambientWash(cornerRadius: cornerRadius)
                }
                .glassEffect(.regular.tint(outerGlassTint), in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(highlightStrokeColor, lineWidth: 0.75)
                }
                .overlay(alignment: .top) {
                    topHighlight
                }
                .shadow(color: shadowColor, radius: 20, x: 0, y: 10)
        } else {
            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(fallbackFillColor)
                        .background {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(.ultraThinMaterial)
                        }
                }
                .overlay {
                    ambientWash(cornerRadius: cornerRadius)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(highlightStrokeColor, lineWidth: 0.75)
                }
                .overlay(alignment: .top) {
                    topHighlight
                }
                .shadow(color: shadowColor, radius: 16, x: 0, y: 8)
        }
    }
}

private struct OverlayInsetSurfaceModifier: ViewModifier {
    let tone: OverlayInsetSurfaceTone
    let colorScheme: ColorScheme
    let cornerRadius: CGFloat

    private var badgeGlassTint: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.11)
            : Color.white.opacity(0.24)
    }

    private var transcriptGlassTint: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.05)
            : Color.white.opacity(0.16)
    }

    private var footerGlassTint: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.04)
            : Color.white.opacity(0.14)
    }

    private var fallbackBadgeFillColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.11)
            : Color.white.opacity(0.24)
    }

    private var fallbackInnerFillColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.white.opacity(0.18)
    }

    private var fallbackFooterFillColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.035)
            : Color.white.opacity(0.10)
    }

    private var softStrokeColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.14)
            : Color.white.opacity(0.24)
    }

    private var transcriptStrokeColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.white.opacity(0.20)
    }

    private var footerStrokeColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.white.opacity(0.16)
    }

    private var topBloomColor: Color {
        Color.white.opacity(colorScheme == .dark ? 0.05 : 0.11)
    }

    private var lowerLiftColor: Color {
        Color.white.opacity(colorScheme == .dark ? 0.015 : 0.035)
    }

    @ViewBuilder
    private func ambientWash(cornerRadius: CGFloat) -> some View {
        ZStack {
            RadialGradient(
                colors: [
                    topBloomColor,
                    topBloomColor.opacity(0.4),
                    Color.clear
                ],
                center: .top,
                startRadius: 0,
                endRadius: 360
            )

            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.012 : 0.035),
                    Color.clear,
                    lowerLiftColor
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var insetTopHighlight: some View {
        Capsule()
            .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.12))
            .frame(height: 0.8)
            .padding(.horizontal, 14)
            .padding(.top, 1)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        switch tone {
        case .command:
            badgeSurface(content)
        case .content:
            transcriptSurface(content)
        case .footer:
            footerSurface(content)
        }
    }

    @ViewBuilder
    private func badgeSurface(_ content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.tint(badgeGlassTint), in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(softStrokeColor, lineWidth: 0.6)
                }
        } else {
            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(fallbackBadgeFillColor)
                        .background {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(.regularMaterial)
                        }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(softStrokeColor, lineWidth: 0.6)
                }
        }
    }

    @ViewBuilder
    private func transcriptSurface(_ content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background {
                    ambientWash(cornerRadius: cornerRadius)
                }
                .glassEffect(.regular.tint(transcriptGlassTint), in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(transcriptStrokeColor, lineWidth: 0.6)
                }
                .overlay(alignment: .top) {
                    insetTopHighlight
                }
        } else {
            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(fallbackInnerFillColor)
                        .background {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(.regularMaterial)
                        }
                }
                .overlay {
                    ambientWash(cornerRadius: cornerRadius)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(transcriptStrokeColor, lineWidth: 0.6)
                }
                .overlay(alignment: .top) {
                    insetTopHighlight
                }
        }
    }

    @ViewBuilder
    private func footerSurface(_ content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.tint(footerGlassTint), in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(footerStrokeColor, lineWidth: 0.5)
                }
        } else {
            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(fallbackFooterFillColor)
                        .background {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(.thinMaterial)
                        }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(footerStrokeColor, lineWidth: 0.5)
                }
        }
    }
}
