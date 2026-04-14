import AppKit
import DriftlyCore
import SwiftUI
import SVGView

struct SourceBadgeModel: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let icon: SourceBadgeIcon
}

enum SourceBadgeIcon: Hashable {
    case none
    case app(bundleID: String)
    case brandAsset(String)
    case brandMonogram(String)
    case system(String)
}

struct SourceBadge: View {
    let badge: SourceBadgeModel

    var body: some View {
        HStack(spacing: 6) {
            if badge.icon != .none {
                SourceBadgeIconView(icon: badge.icon)
            }

            if !isIconOnly {
                Text(badge.label)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 112, alignment: .leading)
            }
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(DriftlyStyle.badgeText)
        .padding(.horizontal, isIconOnly ? 5 : 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(DriftlyStyle.badgeFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(DriftlyStyle.badgeStroke, lineWidth: 1)
        )
        .help(badge.label)
    }

    private var isIconOnly: Bool {
        if case .brandAsset("x") = badge.icon {
            return true
        }
        return false
    }
}

private struct SourceBadgeIconView: View {
    let icon: SourceBadgeIcon

    var body: some View {
        switch icon {
        case .none:
            EmptyView()
        case let .app(bundleID):
            if let image = AppIconCache.shared.icon(for: bundleID) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 15, height: 15)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                fallback
            }
        case let .brandAsset(assetName):
            if let logoURL = BrandLogoRegistry.url(for: assetName) {
                SVGView(contentsOf: logoURL)
                    .frame(width: assetName == "x" ? 13 : 15, height: assetName == "x" ? 13 : 15)
            } else {
                EmptyView()
            }
        case let .brandMonogram(value):
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(DriftlyStyle.badgeFill)
                Text(value)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(DriftlyStyle.badgeText)
            }
            .frame(width: 15, height: 15)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(DriftlyStyle.badgeStroke, lineWidth: 1)
            )
        case let .system(systemName):
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DriftlyStyle.badgeText)
                .frame(width: 15, height: 15)
        }
    }

    private var fallback: some View {
        Image(systemName: "app.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DriftlyStyle.badgeText)
            .frame(width: 15, height: 15)
    }
}

enum SourceBadgeFactory {
    static func badges(for segments: [TimelineSegment]) -> [SourceBadgeModel] {
        if let domain = segments.compactMap(\.domain).first(where: { !$0.isEmpty }) {
            return [identity(for: domain)]
        }

        if let filePath = segments.compactMap(\.filePath).first(where: { !$0.isEmpty }),
           let badge = fileBadge(for: filePath) {
            return [badge]
        }

        if let appName = segments.map(\.appName).first(where: { !$0.isEmpty }) {
            return [identity(for: appName)]
        }

        return []
    }

    private static func identity(for label: String) -> SourceBadgeModel {
        switch label.lowercased() {
        case "new tab", "newtab":
            return SourceBadgeModel(label: "Chrome tab", icon: .brandAsset("chrome"))
        default:
            if let definition = ReviewEntityRegistry.definition(matchingValue: label) {
                return ReviewEntityRegistry.badge(forDefinition: definition)
            }
            return SourceBadgeModel(label: label, icon: .none)
        }
    }

    static func inlineBadge(for value: String) -> SourceBadgeModel? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if ["new tab", "newtab"].contains(trimmed.lowercased()) {
            return identity(for: "new tab")
        }
        if let definition = ReviewEntityRegistry.definition(matchingValue: trimmed) {
            return ReviewEntityRegistry.badge(forDefinition: definition)
        }
        if let badge = fileBadge(for: trimmed) {
            return badge
        }
        return nil
    }

    private static func fileBadge(for value: String) -> SourceBadgeModel? {
        let filename = URL(fileURLWithPath: value).lastPathComponent.lowercased()
        let candidate = filename.isEmpty ? value.lowercased() : filename

        let codeExtensions: Set<String> = [
            "swift", "ts", "tsx", "js", "jsx", "py", "rb", "go", "rs", "java",
            "kt", "json", "yaml", "yml", "toml", "sql", "sh", "bash", "zsh",
            "md", "mdx", "html", "css", "scss"
        ]

        if let ext = candidate.split(separator: ".").last.map(String.init),
           codeExtensions.contains(ext),
           candidate.contains(".") {
            return SourceBadgeModel(label: filename.isEmpty ? value : URL(fileURLWithPath: value).lastPathComponent, icon: .system("chevron.left.forwardslash.chevron.right"))
        }

        return nil
    }
}

enum BrandLogoRegistry {
    static func url(for assetName: String) -> URL? {
        Bundle.module.url(forResource: assetName, withExtension: "svg")
            ?? Bundle.module.url(forResource: assetName, withExtension: "svg", subdirectory: "BrandLogos")
    }
}

final class AppIconCache {
    static let shared = AppIconCache()

    private var cache: [String: NSImage] = [:]

    private init() {}

    func icon(for bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] {
            return cached
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }

        let image = NSWorkspace.shared.icon(forFile: appURL.path)
        image.size = NSSize(width: 24, height: 24)
        cache[bundleID] = image
        return image
    }
}
