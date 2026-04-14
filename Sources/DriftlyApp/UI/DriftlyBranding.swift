import AppKit
import SwiftUI
import SVGView

private enum DriftlyBrandMetrics {
    static let fullMarkAspectRatio: CGFloat = 3.2
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
            .frame(width: 28, height: 8)
    }
}

@MainActor
enum DriftlyBrandImageFactory {
    static let defaultMenuBarImage: NSImage = makeMenuBarImage()

    private static func makeMenuBarImage() -> NSImage {
        let renderer = ImageRenderer(content: DriftlyMenuBarGlyph())
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 28, height: 8))
        image.isTemplate = false
        return image
    }
}
