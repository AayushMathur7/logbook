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
    case rasterAsset(String)
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
        case let .rasterAsset(assetName):
            if let logoURL = BrandLogoRegistry.rasterURL(for: assetName),
               let image = NSImage(contentsOf: logoURL) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 15, height: 15)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
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
    private static let brandAssetIcons: [String: String] = [
        "chrome": "chrome",
        "codex": "codex",
        "claude": "claude",
        "openai": "openai",
        "spotify": "spotify",
        "slack": "slack",
        "linear": "linear",
        "figma": "figma",
        "vercel": "vercel",
        "github": "github",
        "gitlab": "gitlab",
        "youtube": "youtube",
        "gmail": "gmail",
        "gemini": "googlegemini",
        "linkedin": "linkedin",
        "notion": "notion",
        "x": "x",
        "discord": "discord",
        "telegram": "telegram",
        "zoom": "zoom",
        "disneyplus": "disneyplus",
        "resend": "resend",
        "supabase": "supabase",
        "raycast": "raycast",
        "canva": "canva",
        "sentry": "sentry",
        "stripe": "stripe",
        "hugging-face": "huggingface",
        "netlify": "netlify",
        "cloudflare": "cloudflare",
    ]

    private static let rasterAssetIcons: [String: String] = [
        "clicky": "clicky",
    ]

    private static let appBundleIcons: [String: String] = [
        "safari": "com.apple.Safari",
        "cursor": "com.todesktop.230313mzl4w4u92",
        "chatgpt": "com.openai.chat",
        "facetime": "com.apple.FaceTime",
        "messages": "com.apple.MobileSMS",
        "terminal": "com.apple.Terminal",
        "finder": "com.apple.finder",
        "notes": "com.apple.Notes",
        "music": "com.apple.Music",
        "calendar": "com.apple.iCal",
        "preview": "com.apple.Preview",
        "textedit": "com.apple.TextEdit",
        "numbers": "com.apple.iWork.Numbers",
        "pages": "com.apple.iWork.Pages",
        "keynote": "com.apple.iWork.Keynote",
        "whatsapp": "net.whatsapp.WhatsApp",
    ]

    private static let systemIcons: [String: String] = [
        "driftly": "wind",
        "google-calendar": "calendar",
        "google-docs": "doc.text",
        "google-drive": "folder",
    ]

    private static let monogramIcons: [String: String] = [
        "box": "B",
        "jam": "J",
    ]

    static func badges(for segments: [TimelineSegment]) -> [SourceBadgeModel] {
        struct Aggregate {
            var badge: SourceBadgeModel
            var seconds: TimeInterval
        }

        var aggregates: [String: Aggregate] = [:]

        for segment in segments {
            let duration = max(segment.endAt.timeIntervalSince(segment.startAt), 1)
            var candidates: [SourceBadgeModel] = []

            if let domain = segment.domain?.trimmingCharacters(in: .whitespacesAndNewlines),
               !domain.isEmpty {
                candidates.append(identity(for: domain))
            }

            if let filePath = segment.filePath?.trimmingCharacters(in: .whitespacesAndNewlines),
               !filePath.isEmpty,
               let badge = fileBadge(for: filePath) {
                candidates.append(badge)
            }

            let trimmedAppName = segment.appName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedAppName.isEmpty {
                candidates.append(identity(for: trimmedAppName))
            }

            var seenCandidateKeys: Set<String> = []
            for candidate in candidates where candidate.icon != .none {
                let key = badgeKey(for: candidate)
                guard seenCandidateKeys.insert(key).inserted else { continue }

                if var current = aggregates[key] {
                    current.seconds += duration
                    aggregates[key] = current
                } else {
                    aggregates[key] = Aggregate(badge: candidate, seconds: duration)
                }
            }
        }

        return aggregates.values
            .sorted {
                if $0.seconds == $1.seconds {
                    return $0.badge.label.localizedCaseInsensitiveCompare($1.badge.label) == .orderedAscending
                }
                return $0.seconds > $1.seconds
            }
            .prefix(4)
            .map(\.badge)
    }

    private static func identity(for label: String) -> SourceBadgeModel {
        switch label.lowercased() {
        case "new tab", "newtab":
            return SourceBadgeModel(label: "Chrome tab", icon: .brandAsset("chrome"))
        default:
            if let definition = ReviewEntityRegistry.definition(matchingValue: label) {
                return badge(for: definition)
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
            return badge(for: definition)
        }
        if let badge = fileBadge(for: trimmed) {
            return badge
        }
        return nil
    }

    private static func badge(for definition: ReviewEntityDefinition, label: String? = nil) -> SourceBadgeModel {
        SourceBadgeModel(label: label ?? definition.label, icon: icon(for: definition))
    }

    private static func icon(for definition: ReviewEntityDefinition) -> SourceBadgeIcon {
        if let bundleID = appBundleIcons[definition.referenceID] {
            return .app(bundleID: bundleID)
        }
        if let assetName = brandAssetIcons[definition.referenceID] {
            return .brandAsset(assetName)
        }
        if let assetName = rasterAssetIcons[definition.referenceID] {
            return .rasterAsset(assetName)
        }
        if let systemName = systemIcons[definition.referenceID] {
            return .system(systemName)
        }
        if let monogram = monogramIcons[definition.referenceID] {
            return .brandMonogram(monogram)
        }
        return .none
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

    private static func badgeKey(for badge: SourceBadgeModel) -> String {
        let iconKey: String = switch badge.icon {
        case .none:
            "none"
        case let .app(bundleID):
            "app:\(bundleID)"
        case let .brandAsset(assetName):
            "brand:\(assetName)"
        case let .rasterAsset(assetName):
            "raster:\(assetName)"
        case let .brandMonogram(value):
            "monogram:\(value)"
        case let .system(systemName):
            "system:\(systemName)"
        }

        return "\(badge.label.lowercased())|\(iconKey)"
    }
}

enum BrandLogoRegistry {
    static func url(for assetName: String) -> URL? {
        Bundle.module.url(forResource: assetName, withExtension: "svg")
            ?? Bundle.module.url(forResource: assetName, withExtension: "svg", subdirectory: "BrandLogos")
    }

    static func rasterURL(for assetName: String) -> URL? {
        Bundle.module.url(forResource: assetName, withExtension: "png")
            ?? Bundle.module.url(forResource: assetName, withExtension: "png", subdirectory: "BrandLogos")
            ?? Bundle.module.url(forResource: assetName, withExtension: "ico")
            ?? Bundle.module.url(forResource: assetName, withExtension: "ico", subdirectory: "BrandLogos")
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
