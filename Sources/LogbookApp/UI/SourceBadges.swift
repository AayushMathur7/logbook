import AppKit
import LogbookCore
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
        .foregroundStyle(LogbookStyle.badgeText)
        .padding(.horizontal, isIconOnly ? 5 : 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LogbookStyle.badgeFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(LogbookStyle.badgeStroke, lineWidth: 1)
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
                    .fill(LogbookStyle.badgeFill)
                Text(value)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(LogbookStyle.badgeText)
            }
            .frame(width: 15, height: 15)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(LogbookStyle.badgeStroke, lineWidth: 1)
            )
        case let .system(systemName):
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LogbookStyle.badgeText)
                .frame(width: 15, height: 15)
        }
    }

    private var fallback: some View {
        Image(systemName: "app.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(LogbookStyle.badgeText)
            .frame(width: 15, height: 15)
    }
}

enum SourceBadgeFactory {
    static func badges(for segments: [TimelineSegment]) -> [SourceBadgeModel] {
        if let domain = segments.compactMap(\.domain).first(where: { !$0.isEmpty }) {
            return [identity(for: normalizedDomainLabel(domain))]
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

    private static func normalizedDomainLabel(_ domain: String) -> String {
        switch domain.lowercased() {
        case "github.com":
            return "GitHub"
        case "docs.google.com":
            return "Google Docs"
        case "drive.google.com":
            return "Google Drive"
        case "youtube.com", "youtu.be":
            return "YouTube"
        case "x.com", "twitter.com":
            return "X"
        case "calendar.notion.so":
            return "Notion Calendar"
        default:
            return domain.replacingOccurrences(of: "www.", with: "")
        }
    }

    private static func identity(for label: String) -> SourceBadgeModel {
        switch label.lowercased() {
        case "cursor":
            return SourceBadgeModel(label: "Cursor", icon: .app(bundleID: "com.todesktop.230313mzl4w4u92"))
        case "codex":
            return SourceBadgeModel(label: "Codex", icon: .brandAsset("openai"))
        case "google chrome", "chrome":
            return SourceBadgeModel(label: "Chrome", icon: .brandAsset("chrome"))
        case "google docs":
            return SourceBadgeModel(label: "Google Docs", icon: .system("doc.text"))
        case "google drive":
            return SourceBadgeModel(label: "Google Drive", icon: .system("folder"))
        case "github":
            return SourceBadgeModel(label: "GitHub", icon: .brandAsset("github"))
        case "youtube":
            return SourceBadgeModel(label: "YouTube", icon: .brandAsset("youtube"))
        case "x":
            return SourceBadgeModel(label: "X", icon: .brandAsset("x"))
        case "spotify":
            return SourceBadgeModel(label: "Spotify", icon: .brandAsset("spotify"))
        case "whatsapp":
            return SourceBadgeModel(label: "WhatsApp", icon: .app(bundleID: "net.whatsapp.WhatsApp"))
        case "notion calendar":
            return SourceBadgeModel(label: "Notion Calendar", icon: .brandAsset("notion"))
        case "notion":
            return SourceBadgeModel(label: "Notion", icon: .brandAsset("notion"))
        case "finder":
            return SourceBadgeModel(label: "Finder", icon: .app(bundleID: "com.apple.finder"))
        case "terminal":
            return SourceBadgeModel(label: "Terminal", icon: .app(bundleID: "com.apple.Terminal"))
        case "messages":
            return SourceBadgeModel(label: "Messages", icon: .app(bundleID: "com.apple.MobileSMS"))
        case "safari":
            return SourceBadgeModel(label: "Safari", icon: .app(bundleID: "com.apple.Safari"))
        case "log book":
            return SourceBadgeModel(label: "Log Book", icon: .system("book.closed.fill"))
        case "new tab", "newtab":
            return SourceBadgeModel(label: "Chrome tab", icon: .brandAsset("chrome"))
        default:
            return SourceBadgeModel(label: label, icon: .none)
        }
    }

    static func inlineBadge(for value: String) -> SourceBadgeModel? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        if lowered == "new tab" || lowered == "newtab" {
            return identity(for: "new tab")
        }
        if lowered.contains("notion calendar") {
            return SourceBadgeModel(label: "Notion Calendar", icon: .brandAsset("notion"))
        }
        if lowered == "notion" {
            return SourceBadgeModel(label: "Notion", icon: .brandAsset("notion"))
        }
        if lowered.contains("github") {
            return SourceBadgeModel(label: trimmed, icon: .brandAsset("github"))
        }
        if lowered.contains("google doc") || lowered.contains("docs.google") {
            return SourceBadgeModel(label: trimmed, icon: .system("doc.text"))
        }
        if lowered.contains("google drive") || lowered.contains("drive.google") {
            return SourceBadgeModel(label: trimmed, icon: .system("folder"))
        }
        if lowered.contains("youtube") {
            return SourceBadgeModel(label: trimmed, icon: .brandAsset("youtube"))
        }
        if lowered == "x" || lowered.contains(" on x") || lowered.contains("x home") {
            return SourceBadgeModel(label: trimmed, icon: .brandAsset("x"))
        }
        if lowered.contains("spotify") {
            return SourceBadgeModel(label: trimmed, icon: .brandAsset("spotify"))
        }
        if lowered.contains("whatsapp") {
            return SourceBadgeModel(label: trimmed, icon: .app(bundleID: "net.whatsapp.WhatsApp"))
        }
        if lowered.contains("chrome") {
            return SourceBadgeModel(label: trimmed, icon: .brandAsset("chrome"))
        }
        if lowered.contains("cursor") {
            return SourceBadgeModel(label: trimmed, icon: .app(bundleID: "com.todesktop.230313mzl4w4u92"))
        }
        if lowered.contains("codex") {
            return SourceBadgeModel(label: trimmed, icon: .brandAsset("openai"))
        }
        if lowered.contains("log book") || lowered.contains("logbook") {
            return SourceBadgeModel(label: trimmed, icon: .system("book.closed.fill"))
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
