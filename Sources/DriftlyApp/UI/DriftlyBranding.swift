import AppKit
import SwiftUI
import SVGView

private enum DriftlyBrandMetrics {
    static let fullMarkAspectRatio: CGFloat = 3.2
    static let menuBarGlyphWidth: CGFloat = 28
    static let menuBarGlyphHeight: CGFloat = 8
}

struct DriftlyMarkView: View {
    var body: some View {
        DriftlySVGMark(assetName: "driftly-mark-white")
            .aspectRatio(DriftlyBrandMetrics.fullMarkAspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct DriftlyWordmarkView: View {
    var body: some View {
        Text("Driftly")
            .font(.system(size: 16, weight: .medium))
            .kerning(-0.35)
            .foregroundStyle(DriftlyStyle.text)
            .accessibilityHidden(true)
    }
}

private struct DriftlySVGMark: View {
    let assetName: String

    var body: some View {
        if let logoURL = BrandLogoRegistry.url(for: assetName) {
            SVGView(contentsOf: logoURL)
        } else {
            Color.clear
        }
    }
}

private struct DriftlyMenuBarGlyph: View {
    var body: some View {
        DriftlySVGMark(assetName: "driftly-mark-black")
            .frame(width: DriftlyBrandMetrics.menuBarGlyphWidth, height: DriftlyBrandMetrics.menuBarGlyphHeight)
    }
}

private struct DriftlyMenuBarLabel: View {
    let elapsed: String

    var body: some View {
        HStack(spacing: 6) {
            DriftlyMenuBarGlyph()
            Text(elapsed)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.92))
                .monospacedDigit()
                .fixedSize()
        }
        .frame(height: 16)
    }
}

@MainActor
enum DriftlyBrandImageFactory {
    static let defaultMenuBarImage: NSImage = makeMenuBarImage()

    static func sessionMenuBarImage(elapsed: String) -> NSImage {
        makeMenuBarImage(elapsed: elapsed)
    }

    private static func makeMenuBarImage() -> NSImage {
        makeRenderedImage(
            content: DriftlyMenuBarGlyph(),
            fallbackSize: NSSize(
                width: DriftlyBrandMetrics.menuBarGlyphWidth,
                height: DriftlyBrandMetrics.menuBarGlyphHeight
            )
        )
    }

    private static func makeMenuBarImage(elapsed: String) -> NSImage {
        let content = DriftlyMenuBarLabel(elapsed: elapsed)
        let approximateTextWidth = max(CGFloat(elapsed.count) * 8.0, 30)
        return makeRenderedImage(
            content: content,
            fallbackSize: NSSize(
                width: DriftlyBrandMetrics.menuBarGlyphWidth + 6 + approximateTextWidth,
                height: 16
            )
        )
    }

    private static func makeRenderedImage<Content: View>(content: Content, fallbackSize: NSSize) -> NSImage {
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(size: fallbackSize)
        image.isTemplate = false
        return image
    }
}
