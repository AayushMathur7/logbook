import Foundation
import DriftlyCore

enum ReviewEntityKind: String, Hashable {
    case app
    case site
}

struct ReviewEntityDefinition: Hashable {
    let kind: ReviewEntityKind
    let referenceID: String
    let label: String
    let aliases: [String]
    let domains: [String]

    var key: String {
        "\(kind.rawValue):\(referenceID)"
    }

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

struct ReviewEntityPattern: Hashable {
    let label: String
    let kind: ReviewEntityKind
    let referenceID: String
}

enum ReviewEntityRegistry {
    static let entities: [ReviewEntityDefinition] = [
        ReviewEntityDefinition(kind: .app, referenceID: "chrome", label: "Chrome", aliases: ["chrome", "google chrome"], domains: []),
        ReviewEntityDefinition(kind: .app, referenceID: "safari", label: "Safari", aliases: ["safari"], domains: []),
        ReviewEntityDefinition(kind: .app, referenceID: "codex", label: "Codex", aliases: ["codex"], domains: []),
        ReviewEntityDefinition(kind: .app, referenceID: "cursor", label: "Cursor", aliases: ["cursor"], domains: []),
        ReviewEntityDefinition(kind: .app, referenceID: "claude", label: "Claude", aliases: ["claude"], domains: ["claude.ai"]),
        ReviewEntityDefinition(kind: .app, referenceID: "chatgpt", label: "ChatGPT", aliases: ["chatgpt"], domains: ["chatgpt.com"]),
        ReviewEntityDefinition(kind: .app, referenceID: "driftly", label: "Driftly", aliases: ["driftly", "drift ly", "log book", "logbook", "log-book"], domains: []),
        ReviewEntityDefinition(kind: .app, referenceID: "spotify", label: "Spotify", aliases: ["spotify"], domains: ["spotify.com", "open.spotify.com"]),
        ReviewEntityDefinition(kind: .app, referenceID: "slack", label: "Slack", aliases: ["slack"], domains: ["slack.com", "app.slack.com"]),
        ReviewEntityDefinition(kind: .app, referenceID: "linear", label: "Linear", aliases: ["linear"], domains: ["linear.app"]),
        ReviewEntityDefinition(kind: .app, referenceID: "figma", label: "Figma", aliases: ["figma"], domains: ["figma.com"]),
        ReviewEntityDefinition(kind: .app, referenceID: "vercel", label: "Vercel", aliases: ["vercel"], domains: ["vercel.com"]),
        ReviewEntityDefinition(kind: .app, referenceID: "facetime", label: "FaceTime", aliases: ["facetime", "face time"], domains: []),
        ReviewEntityDefinition(kind: .app, referenceID: "messages", label: "Messages", aliases: ["messages"], domains: []),
        ReviewEntityDefinition(kind: .app, referenceID: "terminal", label: "Terminal", aliases: ["terminal"], domains: []),
        ReviewEntityDefinition(kind: .app, referenceID: "finder", label: "Finder", aliases: ["finder"], domains: []),
        ReviewEntityDefinition(kind: .app, referenceID: "notes", label: "Notes", aliases: ["notes", "apple notes"], domains: []),
        ReviewEntityDefinition(kind: .app, referenceID: "music", label: "Music", aliases: ["music", "apple music"], domains: []),
        ReviewEntityDefinition(kind: .app, referenceID: "calendar", label: "Calendar", aliases: ["calendar", "apple calendar"], domains: []),
        ReviewEntityDefinition(kind: .app, referenceID: "preview", label: "Preview", aliases: ["preview"], domains: []),
        ReviewEntityDefinition(kind: .app, referenceID: "textedit", label: "TextEdit", aliases: ["textedit", "text edit"], domains: []),
        ReviewEntityDefinition(kind: .app, referenceID: "numbers", label: "Numbers", aliases: ["numbers"], domains: []),
        ReviewEntityDefinition(kind: .app, referenceID: "pages", label: "Pages", aliases: ["pages"], domains: []),
        ReviewEntityDefinition(kind: .app, referenceID: "keynote", label: "Keynote", aliases: ["keynote"], domains: []),
        ReviewEntityDefinition(kind: .site, referenceID: "github", label: "GitHub", aliases: ["github"], domains: ["github.com"]),
        ReviewEntityDefinition(kind: .site, referenceID: "youtube", label: "YouTube", aliases: ["youtube", "youtube shorts"], domains: ["youtube.com", "youtu.be"]),
        ReviewEntityDefinition(kind: .site, referenceID: "gmail", label: "Gmail", aliases: ["gmail"], domains: ["mail.google.com"]),
        ReviewEntityDefinition(kind: .site, referenceID: "google-calendar", label: "Google Calendar", aliases: ["google calendar"], domains: ["calendar.google.com"]),
        ReviewEntityDefinition(kind: .site, referenceID: "google-docs", label: "Google Docs", aliases: ["google docs", "google doc"], domains: ["docs.google.com"]),
        ReviewEntityDefinition(kind: .site, referenceID: "google-drive", label: "Google Drive", aliases: ["google drive"], domains: ["drive.google.com"]),
        ReviewEntityDefinition(kind: .site, referenceID: "notion", label: "Notion", aliases: ["notion"], domains: ["notion.so", "notion.site"]),
        ReviewEntityDefinition(kind: .site, referenceID: "notion-calendar", label: "Notion Calendar", aliases: ["notion calendar"], domains: ["calendar.notion.so"]),
        ReviewEntityDefinition(kind: .site, referenceID: "x", label: "X", aliases: ["x", "twitter"], domains: ["x.com", "twitter.com"]),
        ReviewEntityDefinition(kind: .site, referenceID: "whatsapp", label: "WhatsApp", aliases: ["whatsapp"], domains: ["web.whatsapp.com"]),
        ReviewEntityDefinition(kind: .site, referenceID: "discord", label: "Discord", aliases: ["discord"], domains: ["discord.com", "discordapp.com"]),
        ReviewEntityDefinition(kind: .site, referenceID: "supabase", label: "Supabase", aliases: ["supabase"], domains: ["supabase.com"]),
        ReviewEntityDefinition(kind: .site, referenceID: "raycast", label: "Raycast", aliases: ["raycast"], domains: ["raycast.com"]),
        ReviewEntityDefinition(kind: .site, referenceID: "canva", label: "Canva", aliases: ["canva"], domains: ["canva.com"]),
        ReviewEntityDefinition(kind: .site, referenceID: "sentry", label: "Sentry", aliases: ["sentry"], domains: ["sentry.io"]),
        ReviewEntityDefinition(kind: .site, referenceID: "stripe", label: "Stripe", aliases: ["stripe"], domains: ["stripe.com"]),
        ReviewEntityDefinition(kind: .site, referenceID: "box", label: "Box", aliases: ["box"], domains: ["box.com", "app.box.com"]),
        ReviewEntityDefinition(kind: .site, referenceID: "jam", label: "Jam", aliases: ["jam"], domains: ["jam.dev"]),
        ReviewEntityDefinition(kind: .site, referenceID: "hugging-face", label: "Hugging Face", aliases: ["hugging face", "huggingface"], domains: ["huggingface.co"]),
        ReviewEntityDefinition(kind: .site, referenceID: "netlify", label: "Netlify", aliases: ["netlify"], domains: ["netlify.com", "app.netlify.com"]),
        ReviewEntityDefinition(kind: .site, referenceID: "cloudflare", label: "Cloudflare", aliases: ["cloudflare"], domains: ["cloudflare.com", "dash.cloudflare.com"]),
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

            guard seen.insert(definition.key).inserted else { continue }
            matches.append(definition)
        }

        return Array(matches.prefix(12))
    }

    static func inferredEntityPatterns() -> [ReviewEntityPattern] {
        entities.flatMap { definition in
            definition.allLabels.map { label in
                ReviewEntityPattern(label: label, kind: definition.kind, referenceID: definition.referenceID)
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
