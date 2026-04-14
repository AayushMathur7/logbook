import Foundation
import DriftlyCore

struct ReviewEntityDefinition: Hashable {
    let kind: String
    let referenceID: String
    let label: String
    let aliases: [String]
    let domains: [String]
    let icon: SourceBadgeIcon

    var allLabels: [String] {
        var seen: Set<String> = []
        var output: [String] = []

        for value in [label] + aliases {
            let normalized = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            guard !normalized.isEmpty else { continue }
            guard seen.insert(normalized).inserted else { continue }
            output.append(value)
        }

        return output
    }
}

enum ReviewEntityRegistry {
    static let entities: [ReviewEntityDefinition] = [
        ReviewEntityDefinition(kind: "app", referenceID: "chrome", label: "Chrome", aliases: ["chrome", "google chrome"], domains: [], icon: .brandAsset("chrome")),
        ReviewEntityDefinition(kind: "app", referenceID: "safari", label: "Safari", aliases: ["safari"], domains: [], icon: .app(bundleID: "com.apple.Safari")),
        ReviewEntityDefinition(kind: "app", referenceID: "codex", label: "Codex", aliases: ["codex"], domains: [], icon: .brandAsset("codex")),
        ReviewEntityDefinition(kind: "app", referenceID: "cursor", label: "Cursor", aliases: ["cursor"], domains: [], icon: .app(bundleID: "com.todesktop.230313mzl4w4u92")),
        ReviewEntityDefinition(kind: "app", referenceID: "claude", label: "Claude", aliases: ["claude"], domains: ["claude.ai"], icon: .brandAsset("claude")),
        ReviewEntityDefinition(kind: "app", referenceID: "chatgpt", label: "ChatGPT", aliases: ["chatgpt"], domains: ["chatgpt.com"], icon: .app(bundleID: "com.openai.chat")),
        ReviewEntityDefinition(kind: "app", referenceID: "driftly", label: "Driftly", aliases: ["driftly", "drift ly", "log book", "logbook", "log-book"], domains: [], icon: .system("wind")),
        ReviewEntityDefinition(kind: "app", referenceID: "spotify", label: "Spotify", aliases: ["spotify"], domains: ["spotify.com", "open.spotify.com"], icon: .brandAsset("spotify")),
        ReviewEntityDefinition(kind: "app", referenceID: "slack", label: "Slack", aliases: ["slack"], domains: ["slack.com", "app.slack.com"], icon: .brandAsset("slack")),
        ReviewEntityDefinition(kind: "app", referenceID: "linear", label: "Linear", aliases: ["linear"], domains: ["linear.app"], icon: .brandAsset("linear")),
        ReviewEntityDefinition(kind: "app", referenceID: "figma", label: "Figma", aliases: ["figma"], domains: ["figma.com"], icon: .brandAsset("figma")),
        ReviewEntityDefinition(kind: "app", referenceID: "vercel", label: "Vercel", aliases: ["vercel"], domains: ["vercel.com"], icon: .brandAsset("vercel")),
        ReviewEntityDefinition(kind: "app", referenceID: "facetime", label: "FaceTime", aliases: ["facetime", "face time"], domains: [], icon: .app(bundleID: "com.apple.FaceTime")),
        ReviewEntityDefinition(kind: "app", referenceID: "messages", label: "Messages", aliases: ["messages"], domains: [], icon: .app(bundleID: "com.apple.MobileSMS")),
        ReviewEntityDefinition(kind: "app", referenceID: "terminal", label: "Terminal", aliases: ["terminal"], domains: [], icon: .app(bundleID: "com.apple.Terminal")),
        ReviewEntityDefinition(kind: "app", referenceID: "finder", label: "Finder", aliases: ["finder"], domains: [], icon: .app(bundleID: "com.apple.finder")),
        ReviewEntityDefinition(kind: "app", referenceID: "notes", label: "Notes", aliases: ["notes", "apple notes"], domains: [], icon: .app(bundleID: "com.apple.Notes")),
        ReviewEntityDefinition(kind: "app", referenceID: "music", label: "Music", aliases: ["music", "apple music"], domains: [], icon: .app(bundleID: "com.apple.Music")),
        ReviewEntityDefinition(kind: "app", referenceID: "calendar", label: "Calendar", aliases: ["calendar", "apple calendar"], domains: [], icon: .app(bundleID: "com.apple.iCal")),
        ReviewEntityDefinition(kind: "app", referenceID: "preview", label: "Preview", aliases: ["preview"], domains: [], icon: .app(bundleID: "com.apple.Preview")),
        ReviewEntityDefinition(kind: "app", referenceID: "textedit", label: "TextEdit", aliases: ["textedit", "text edit"], domains: [], icon: .app(bundleID: "com.apple.TextEdit")),
        ReviewEntityDefinition(kind: "app", referenceID: "numbers", label: "Numbers", aliases: ["numbers"], domains: [], icon: .app(bundleID: "com.apple.iWork.Numbers")),
        ReviewEntityDefinition(kind: "app", referenceID: "pages", label: "Pages", aliases: ["pages"], domains: [], icon: .app(bundleID: "com.apple.iWork.Pages")),
        ReviewEntityDefinition(kind: "app", referenceID: "keynote", label: "Keynote", aliases: ["keynote"], domains: [], icon: .app(bundleID: "com.apple.iWork.Keynote")),
        ReviewEntityDefinition(kind: "site", referenceID: "github", label: "GitHub", aliases: ["github"], domains: ["github.com"], icon: .brandAsset("github")),
        ReviewEntityDefinition(kind: "site", referenceID: "youtube", label: "YouTube", aliases: ["youtube", "youtube shorts"], domains: ["youtube.com", "youtu.be"], icon: .brandAsset("youtube")),
        ReviewEntityDefinition(kind: "site", referenceID: "gmail", label: "Gmail", aliases: ["gmail"], domains: ["mail.google.com"], icon: .brandAsset("gmail")),
        ReviewEntityDefinition(kind: "site", referenceID: "google-calendar", label: "Google Calendar", aliases: ["google calendar"], domains: ["calendar.google.com"], icon: .system("calendar")),
        ReviewEntityDefinition(kind: "site", referenceID: "google-docs", label: "Google Docs", aliases: ["google docs", "google doc"], domains: ["docs.google.com"], icon: .system("doc.text")),
        ReviewEntityDefinition(kind: "site", referenceID: "google-drive", label: "Google Drive", aliases: ["google drive"], domains: ["drive.google.com"], icon: .system("folder")),
        ReviewEntityDefinition(kind: "site", referenceID: "notion", label: "Notion", aliases: ["notion"], domains: ["notion.so", "notion.site"], icon: .brandAsset("notion")),
        ReviewEntityDefinition(kind: "site", referenceID: "notion-calendar", label: "Notion Calendar", aliases: ["notion calendar"], domains: ["calendar.notion.so"], icon: .brandAsset("notion")),
        ReviewEntityDefinition(kind: "site", referenceID: "x", label: "X", aliases: ["x", "twitter"], domains: ["x.com", "twitter.com"], icon: .brandAsset("x")),
        ReviewEntityDefinition(kind: "site", referenceID: "whatsapp", label: "WhatsApp", aliases: ["whatsapp"], domains: ["web.whatsapp.com"], icon: .app(bundleID: "net.whatsapp.WhatsApp")),
        ReviewEntityDefinition(kind: "site", referenceID: "discord", label: "Discord", aliases: ["discord"], domains: ["discord.com", "discordapp.com"], icon: .brandAsset("discord")),
        ReviewEntityDefinition(kind: "site", referenceID: "supabase", label: "Supabase", aliases: ["supabase"], domains: ["supabase.com"], icon: .brandAsset("supabase")),
        ReviewEntityDefinition(kind: "site", referenceID: "raycast", label: "Raycast", aliases: ["raycast"], domains: ["raycast.com"], icon: .brandAsset("raycast")),
        ReviewEntityDefinition(kind: "site", referenceID: "canva", label: "Canva", aliases: ["canva"], domains: ["canva.com"], icon: .brandAsset("canva")),
        ReviewEntityDefinition(kind: "site", referenceID: "sentry", label: "Sentry", aliases: ["sentry"], domains: ["sentry.io"], icon: .brandAsset("sentry")),
        ReviewEntityDefinition(kind: "site", referenceID: "stripe", label: "Stripe", aliases: ["stripe"], domains: ["stripe.com"], icon: .brandAsset("stripe")),
        ReviewEntityDefinition(kind: "site", referenceID: "box", label: "Box", aliases: ["box"], domains: ["box.com", "app.box.com"], icon: .brandMonogram("B")),
        ReviewEntityDefinition(kind: "site", referenceID: "jam", label: "Jam", aliases: ["jam"], domains: ["jam.dev"], icon: .brandMonogram("J")),
        ReviewEntityDefinition(kind: "site", referenceID: "hugging-face", label: "Hugging Face", aliases: ["hugging face", "huggingface"], domains: ["huggingface.co"], icon: .brandAsset("huggingface")),
        ReviewEntityDefinition(kind: "site", referenceID: "netlify", label: "Netlify", aliases: ["netlify"], domains: ["netlify.com", "app.netlify.com"], icon: .brandAsset("netlify")),
        ReviewEntityDefinition(kind: "site", referenceID: "cloudflare", label: "Cloudflare", aliases: ["cloudflare"], domains: ["cloudflare.com", "dash.cloudflare.com"], icon: .brandAsset("cloudflare"))
    ]

    static func definition(forReferenceID referenceID: String) -> ReviewEntityDefinition? {
        entities.first { $0.referenceID == normalizedToken(referenceID) }
    }

    static func definition(matchingValue value: String) -> ReviewEntityDefinition? {
        let normalized = normalizedText(value)
        guard !normalized.isEmpty else { return nil }

        if let host = normalizedHost(from: value), let domainMatch = definition(forHost: host) {
            return domainMatch
        }

        return entities.first { entity in
            entity.allLabels.contains { alias in
                matchesAlias(alias, in: normalized)
            }
        }
    }

    static func definition(forHost host: String) -> ReviewEntityDefinition? {
        let normalized = normalizedHost(from: host) ?? normalizedText(host)
        guard !normalized.isEmpty else { return nil }

        if normalized.hasSuffix(".vercel.app") {
            return definition(forReferenceID: "vercel")
        }

        return entities.first { entity in
            entity.domains.contains { domain in
                let normalizedDomain = normalizedText(domain)
                return normalized == normalizedDomain || normalized.hasSuffix(".\(normalizedDomain)")
            }
        }
    }

    static func allowedEntities(
        from segments: [TimelineSegment],
        events: [ActivityEvent]
    ) -> [ReviewEntityDefinition] {
        let textCorpus = (
            segments.flatMap {
                [
                    $0.appName,
                    $0.primaryLabel,
                    $0.secondaryLabel,
                    $0.repoName,
                    $0.domain,
                ].compactMap { $0?.lowercased() }
            } +
            events.flatMap {
                [
                    $0.appName,
                    $0.windowTitle,
                    $0.resourceTitle,
                    $0.domain,
                ].compactMap { $0?.lowercased() }
            }
        )

        var matches: [ReviewEntityDefinition] = []
        var seen: Set<String> = []

        for definition in entities {
            let hasAliasMatch = definition.aliases.contains { alias in
                textCorpus.contains { value in
                    matchesAlias(alias, in: normalizedText(value))
                }
            }
            let hasDomainMatch = definition.domains.contains { domain in
                let normalizedDomain = normalizedText(domain)
                return textCorpus.contains { value in normalizedText(value).contains(normalizedDomain) }
            }
            guard hasAliasMatch || hasDomainMatch else { continue }

            let key = "\(definition.kind):\(definition.referenceID)"
            guard seen.insert(key).inserted else { continue }
            matches.append(definition)
        }

        return Array(matches.prefix(12))
    }

    static func promptEntities() -> [ReviewEntityDefinition] {
        entities
    }

    static func badge(forDefinition definition: ReviewEntityDefinition, label: String? = nil) -> SourceBadgeModel {
        SourceBadgeModel(label: label ?? definition.label, icon: definition.icon)
    }

    static func iconDescription(for definition: ReviewEntityDefinition) -> String {
        switch definition.icon {
        case let .brandAsset(assetName):
            return "\(assetName) logo chip"
        case .app:
            return "native app icon chip"
        case .brandMonogram:
            return "monogram chip"
        case .system:
            return "system icon chip"
        case .none:
            return "text chip"
        }
    }

    static func inferredEntityPatterns() -> [(label: String, kind: String, ref: String)] {
        entities.flatMap { definition in
            definition.allLabels.map { label in
                (label: label, kind: definition.kind, ref: definition.referenceID)
            }
        }
        .sorted { lhs, rhs in
            if lhs.label.count == rhs.label.count {
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
            return lhs.label.count > rhs.label.count
        }
    }

    private static func normalizedToken(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func normalizedHost(from value: String) -> String? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        let host = normalized
            .split(separator: "/")
            .first
            .map(String.init)?
            .replacingOccurrences(of: "www.", with: "")
        guard let host, !host.isEmpty else { return nil }
        return host
    }

    private static func matchesAlias(_ alias: String, in normalizedValue: String) -> Bool {
        let normalizedAlias = normalizedText(alias)
        guard !normalizedAlias.isEmpty else { return false }

        if normalizedAlias.count <= 2 {
            let escaped = NSRegularExpression.escapedPattern(for: normalizedAlias)
            let pattern = "(^|\\b)\(escaped)(\\b|$)"
            return normalizedValue.range(of: pattern, options: .regularExpression) != nil
        }

        return normalizedValue == normalizedAlias || normalizedValue.contains(normalizedAlias)
    }
}
