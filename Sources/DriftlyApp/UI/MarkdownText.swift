import Foundation
import DriftlyCore
import SwiftUI
import SVGView

struct MarkdownText: View {
    let markdown: String
    let font: Font
    let color: Color
    var lineLimit: Int? = nil
    var codePointSize: CGFloat = 12
    var inferBadges = false
    var useAttributedLayout = false

    init(
        _ markdown: String,
        font: Font,
        color: Color = .primary,
        lineLimit: Int? = nil,
        codePointSize: CGFloat = 12,
        inferBadges: Bool = false,
        useAttributedLayout: Bool = false
    ) {
        self.markdown = markdown
        self.font = font
        self.color = color
        self.lineLimit = lineLimit
        self.codePointSize = codePointSize
        self.inferBadges = inferBadges
        self.useAttributedLayout = useAttributedLayout
    }

    var body: some View {
        if lineLimit != nil || useAttributedLayout {
            Text(attributedMarkdown)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            MarkdownFlowText(
                markdown: markdown,
                font: font,
                color: color,
                codePointSize: codePointSize,
                inferBadges: inferBadges
            )
        }
    }

    private var attributedMarkdown: AttributedString {
        var attributed = AttributedString()
        for segment in MarkdownHighlightParser.attributedSegments(from: markdown) {
            var part = baseAttributedMarkdown(for: segment.text)

            if segment.isHighlight {
                part.foregroundColor = DriftlyStyle.text
            }

            attributed.append(part)
        }

        return attributed
    }

    private func baseAttributedMarkdown(for value: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var attributed = (try? AttributedString(markdown: value, options: options)) ?? AttributedString(value)

        for run in attributed.runs {
            if run.link != nil {
                attributed[run.range].foregroundColor = subtleLinkColor
                attributed[run.range].underlineStyle = .single
                continue
            }

            guard let intent = run.inlinePresentationIntent else { continue }
            if intent.contains(.code) {
                let token = String(attributed[run.range].characters)
                attributed[run.range].foregroundColor = InlineSemanticColor.color(for: token)
                attributed[run.range].backgroundColor = DriftlyStyle.inlineCodeFill
                attributed[run.range].font = .system(size: codePointSize, weight: .medium, design: .monospaced)
            } else if intent.contains(.stronglyEmphasized) {
                attributed[run.range].foregroundColor = DriftlyStyle.text
            } else if intent.contains(.emphasized) {
                let token = String(attributed[run.range].characters)
                attributed[run.range].foregroundColor = InlineSemanticColor.color(for: token).opacity(0.92)
            }
        }

        return attributed
    }

    private var subtleLinkColor: Color {
        DriftlyStyle.subtleText.opacity(0.94)
    }
}

struct MarkdownFlowText: View {
    let markdown: String
    let font: Font
    let color: Color
    let codePointSize: CGFloat
    let inferBadges: Bool

    private var lines: [[InlineToken]] {
        markdown
            .components(separatedBy: .newlines)
            .map { line in
                MarkdownInlineParser.tokens(from: line, inferBadges: inferBadges)
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, tokens in
                InlineWrapLayout(horizontalSpacing: 0, verticalSpacing: 4) {
                    ForEach(tokens) { token in
                        InlineTokenView(
                            token: token,
                            font: font,
                            color: color,
                            codePointSize: codePointSize
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RichReviewText: View {
    enum EntityStyle {
        case badge
        case inlineChip
        case plain
    }

    let spans: [SessionReviewInlineSpan]
    let fallbackMarkdown: String
    let font: Font
    let color: Color
    var codePointSize: CGFloat = 12
    var entityStyle: EntityStyle = .badge

    init(
        spans: [SessionReviewInlineSpan],
        fallbackMarkdown: String,
        font: Font,
        color: Color = .primary,
        codePointSize: CGFloat = 12,
        entityStyle: EntityStyle = .badge
    ) {
        self.spans = spans
        self.fallbackMarkdown = fallbackMarkdown
        self.font = font
        self.color = color
        self.codePointSize = codePointSize
        self.entityStyle = entityStyle
    }

    var body: some View {
        if spans.isEmpty {
            MarkdownText(fallbackMarkdown, font: font, color: color, codePointSize: codePointSize)
        } else {
            InlineWrapLayout(horizontalSpacing: 0, verticalSpacing: 4) {
                ForEach(Array(reviewFlowTokens.enumerated()), id: \.offset) { _, token in
                    RichReviewTokenView(
                        token: token,
                        font: font,
                        color: color,
                        codePointSize: codePointSize,
                        entityStyle: entityStyle
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var reviewFlowTokens: [RichReviewFlowToken] {
        let rawTokens = spans.flatMap { span in
            flowTokens(for: span)
        }
        if entityStyle == .plain {
            return mergedTrailingPunctuationTokens(rawTokens)
        }
        return mergedTrailingPunctuationTokens(mergedEntityPhraseTokens(rawTokens))
    }

    private func flowTokens(for span: SessionReviewInlineSpan) -> [RichReviewFlowToken] {
        switch span.kind {
        case .text:
            return flowTokens(fromMarkdown: span.text)
        case .entity:
            return [.entity(text: span.text, badge: SourceBadgeFactory.inlineBadge(for: span.text), url: span.url)]
        case .link:
            return [.link(span.text, url: span.url ?? "")]
        case .title:
            if let url = span.url, !url.isEmpty {
                return [.link(span.text, url: url)]
            }
            return [.strong(span.text)]
        case .goal:
            return flowTokens(fromMarkdown: "**\(span.text)**")
        case .code, .file:
            return [.code(span.text, url: span.url)]
        }
    }

    private func flowTokens(fromMarkdown markdown: String) -> [RichReviewFlowToken] {
        MarkdownInlineParser.tokens(from: markdown, inferBadges: false).map { token in
            switch token.kind {
            case let .text(value):
                return .text(value)
            case let .strong(value):
                return .strong(value)
            case let .emphasis(value):
                return .emphasis(value, url: nil)
            case let .code(value):
                return .code(value, url: nil)
            case let .highlight(value):
                return .text(value)
            case let .link(text, url):
                return .link(text, url: url)
            case let .badge(badge):
                return .entity(text: badge.label, badge: badge, url: nil)
            }
        }
    }
}

private struct InlineTokenView: View {
    @Environment(\.openURL) private var openURL

    let token: InlineToken
    let font: Font
    let color: Color
    let codePointSize: CGFloat

    var body: some View {
        switch token.kind {
        case let .text(value):
            Text(verbatim: value)
                .font(font)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        case let .strong(value):
            Text(verbatim: value)
                .font(font)
                .foregroundStyle(DriftlyStyle.text)
                .fixedSize(horizontal: false, vertical: true)
        case let .emphasis(value):
            Text(verbatim: value)
                .font(font)
                .italic()
                .foregroundStyle(InlineSemanticColor.color(for: value).opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        case let .code(value):
            Text(value)
                .font(DriftlyStyle.codeFont(size: codePointSize, weight: .medium))
                .foregroundStyle(InlineSemanticColor.color(for: value))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(DriftlyStyle.inlineCodeFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(DriftlyStyle.inlineCodeStroke, lineWidth: 1)
                )
                .fixedSize()
        case let .highlight(value):
            Text(value)
                .font(font)
                .foregroundStyle(DriftlyStyle.text)
                .fixedSize(horizontal: false, vertical: true)
        case let .link(text, urlString):
            if let url = URL(string: urlString) {
                Button {
                    openURL(url)
                } label: {
                    Text(verbatim: text)
                        .font(font)
                        .foregroundStyle(DriftlyStyle.subtleText.opacity(0.94))
                        .underline()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                .help(urlString)
            } else {
                Text(verbatim: text)
                    .font(font)
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case let .badge(badge):
            SourceBadge(badge: badge)
                .padding(.horizontal, 2)
                .fixedSize()
        }
    }
}

private enum RichReviewFlowToken {
    case text(String)
    case strong(String)
    case emphasis(String, url: String?)
    case code(String, url: String?)
    case link(String, url: String)
    case entity(text: String, badge: SourceBadgeModel?, url: String?)
    case entityPhrase(lead: String?, text: String, badge: SourceBadgeModel?, trail: String?, url: String?)
}

private struct RichReviewTokenView: View {
    @Environment(\.openURL) private var openURL

    let token: RichReviewFlowToken
    let font: Font
    let color: Color
    let codePointSize: CGFloat
    let entityStyle: RichReviewText.EntityStyle

    var body: some View {
        switch token {
        case let .text(value):
            reviewText(value, color: color)
        case let .strong(value):
            reviewText(value, color: DriftlyStyle.text)
        case let .emphasis(value, url):
            linkedText(
                value,
                urlString: url,
                font: font,
                color: InlineSemanticColor.color(for: value).opacity(0.92),
                italic: true,
                underline: false
            )
        case let .entity(text, badge, url):
            if let badge {
                switch entityStyle {
                case .badge:
                    linkedBadge(SourceBadge(badge: badge), urlString: url)
                case .inlineChip:
                    linkedBadge(InlineEntityChip(badge: badge, font: font, isLinked: url != nil), urlString: url)
                case .plain:
                    linkedText(text, urlString: url, font: font, color: color)
                }
            } else {
                linkedText(text, urlString: url, font: font, color: color)
            }
        case let .entityPhrase(lead, text, badge, trail, url):
            HStack(spacing: 4) {
                if let lead, !lead.isEmpty {
                    Text(verbatim: lead)
                        .font(font)
                        .foregroundStyle(color)
                        .fixedSize()
                }

                if let badge {
                    switch entityStyle {
                    case .badge:
                        linkedBadge(SourceBadge(badge: badge), urlString: url)
                    case .inlineChip:
                        linkedBadge(InlineEntityChip(badge: badge, font: font, isLinked: url != nil), urlString: url)
                    case .plain:
                        linkedText(text, urlString: url, font: font, color: color)
                    }
                } else {
                    linkedText(text, urlString: url, font: font, color: color)
                }

                if let trail, !trail.isEmpty {
                    Text(verbatim: trail)
                        .font(font)
                        .foregroundStyle(color)
                        .fixedSize()
                }
            }
            .fixedSize()
        case let .code(value, url):
            linkedCode(value, urlString: url)
        case let .link(value, url):
            linkedText(
                value,
                urlString: url,
                font: font,
                color: DriftlyStyle.subtleText.opacity(0.94),
                underline: true
            )
        }
    }

    private func reviewText(_ value: String, color: Color) -> some View {
        Text(verbatim: value)
            .font(font)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func linkedText(
        _ value: String,
        urlString: String?,
        font: Font,
        color: Color,
        italic: Bool = false,
        underline: Bool = false
    ) -> some View {
        let base = Text(verbatim: value)
            .font(font)
            .foregroundStyle(color)
            .underline(underline && urlString != nil)
            .italic(italic)
            .fixedSize(horizontal: false, vertical: true)

        if let urlString, let url = URL(string: urlString) {
            Button {
                openURL(url)
            } label: {
                base
            }
            .buttonStyle(.plain)
            .help(urlString)
        } else {
            base
        }
    }

    @ViewBuilder
    private func linkedBadge<V: View>(_ view: V, urlString: String?) -> some View {
        if let urlString, let url = URL(string: urlString) {
            Button {
                openURL(url)
            } label: {
                view
            }
            .padding(.horizontal, 2)
            .buttonStyle(.plain)
            .help(urlString)
        } else {
            view
                .padding(.horizontal, 2)
                .fixedSize()
        }
    }

    @ViewBuilder
    private func linkedCode(_ value: String, urlString: String?) -> some View {
        let codeView = Text(value)
            .font(DriftlyStyle.codeFont(size: codePointSize, weight: .medium))
            .foregroundStyle(InlineSemanticColor.color(for: value))
            .underline(urlString != nil)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(DriftlyStyle.inlineCodeFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(DriftlyStyle.inlineCodeStroke, lineWidth: 1)
            )
            .fixedSize()

        if let urlString, let url = URL(string: urlString) {
            Button {
                openURL(url)
            } label: {
                codeView
            }
            .buttonStyle(.plain)
            .help(urlString)
        } else {
            codeView
        }
    }
}

private struct InlineEntityChip: View {
    let badge: SourceBadgeModel
    let font: Font
    var isLinked = false

    var body: some View {
        HStack(spacing: 4) {
            if badge.icon != .none {
                InlineEntityChipIcon(icon: badge.icon)
            }

            if !isIconOnly {
                Text(shortLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(DriftlyStyle.subtleText)
        .padding(.horizontal, isIconOnly ? 4 : 5)
        .padding(.vertical, 1.5)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(DriftlyStyle.badgeFill.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(DriftlyStyle.badgeStroke.opacity(0.65), lineWidth: 1)
        )
        .help(badge.label)
        .fixedSize()
    }

    private var shortLabel: String {
        if badge.label == "Driftly" {
            return "Driftly"
        }
        return badge.label
    }

    private var isIconOnly: Bool {
        if case .brandAsset("x") = badge.icon {
            return true
        }
        return false
    }
}

private struct InlineEntityChipIcon: View {
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
                    .frame(width: 11, height: 11)
                    .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
            }
        case let .brandAsset(assetName):
            if let logoURL = BrandLogoRegistry.url(for: assetName) {
                SVGView(contentsOf: logoURL)
                    .frame(width: assetName == "x" ? 10 : 11, height: assetName == "x" ? 10 : 11)
            }
        case let .rasterAsset(assetName):
            if let logoURL = BrandLogoRegistry.rasterURL(for: assetName),
               let image = NSImage(contentsOf: logoURL) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 11, height: 11)
                    .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
            }
        case let .brandMonogram(value):
            ZStack {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(DriftlyStyle.badgeFill.opacity(0.8))
                Text(value)
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundStyle(DriftlyStyle.subtleText)
            }
            .frame(width: 11, height: 11)
        case let .system(systemName):
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DriftlyStyle.subtleText)
                .frame(width: 11, height: 11)
        }
    }
}

private struct InlineWrapLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    init(horizontalSpacing: CGFloat = 4, verticalSpacing: CGFloat = 4) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout Void
    ) -> CGSize {
        layout(in: CGRect(origin: .zero, size: CGSize(width: proposal.width ?? .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)), subviews: subviews, place: false)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout Void
    ) {
        _ = layout(in: bounds, subviews: subviews, place: true)
    }

    private func layout(in bounds: CGRect, subviews: Subviews, place: Bool) -> CGSize {
        let maxWidth = bounds.width.isFinite ? bounds.width : .greatestFiniteMagnitude
        var origin = bounds.origin
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let idealSize = subview.sizeThatFits(.unspecified)
            let remainingLineWidth = max(bounds.minX + maxWidth - origin.x, 0)
            let fittingWidth = origin.x > bounds.minX ? remainingLineWidth : maxWidth
            var size = idealSize
            var wrappedInRemainingWidth = false

            if fittingWidth.isFinite, fittingWidth > 0, idealSize.width > fittingWidth {
                size = subview.sizeThatFits(
                    ProposedViewSize(width: fittingWidth, height: nil)
                )
                wrappedInRemainingWidth = size.height > idealSize.height
            }

            if origin.x > bounds.minX,
               (origin.x + size.width > bounds.minX + maxWidth || wrappedInRemainingWidth) {
                origin.x = bounds.minX
                origin.y += lineHeight + verticalSpacing
                lineHeight = 0

                let wrappedIdealSize = subview.sizeThatFits(.unspecified)
                if wrappedIdealSize.width > maxWidth {
                    size = subview.sizeThatFits(
                        ProposedViewSize(width: maxWidth, height: nil)
                    )
                } else {
                    size = wrappedIdealSize
                }
            }

            if place {
                subview.place(
                    at: origin,
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: size.width, height: size.height)
                )
            }

            usedWidth = max(usedWidth, origin.x - bounds.minX + size.width)
            origin.x += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(
            width: usedWidth,
            height: max(origin.y - bounds.minY + lineHeight, 0)
        )
    }
}

private enum InlineSemanticColor {
    static func color(for value: String) -> Color {
        let lowered = value.lowercased()

        if lowered.contains("spotify") {
            return DriftlyStyle.badgeGreenText
        }

        if lowered.contains("youtube") || lowered.contains("notion") || lowered == "x" || lowered.contains(" x ") || lowered.contains("http") || lowered.contains(".com") {
            return DriftlyStyle.badgeWarmText
        }

        if lowered.contains("github") || lowered.contains("cursor") || lowered.contains("chrome") || lowered.contains("codex") || lowered.contains("/") || lowered.contains(".swift") || lowered.contains(".md") {
            return DriftlyStyle.badgeBlueText
        }

        return DriftlyStyle.inlineCodeText
    }
}

private func mergedEntityPhraseTokens(_ tokens: [RichReviewFlowToken]) -> [RichReviewFlowToken] {
    var result: [RichReviewFlowToken] = []
    var index = 0

    while index < tokens.count {
        let token = tokens[index]

        guard case let .entity(text, badge, url) = token else {
            result.append(token)
            index += 1
            continue
        }

        var lead: String?
        if let last = result.last,
           case let .text(previousText) = last,
           let split = splitTrailingEntityLead(in: previousText) {
            result.removeLast()
            if !split.prefix.isEmpty {
                result.append(.text(split.prefix))
            }
            lead = split.lead
        }

        var trail: String?
        if index + 1 < tokens.count,
           case let .text(nextText) = tokens[index + 1],
           let split = splitLeadingEntityTrail(in: nextText) {
            trail = split.trail
            if !split.remainder.isEmpty {
                result.append(.entityPhrase(lead: lead, text: text, badge: badge, trail: trail, url: url))
                result.append(.text(split.remainder))
                index += 2
                continue
            }
            index += 2
            result.append(.entityPhrase(lead: lead, text: text, badge: badge, trail: trail, url: url))
            continue
        }

        if lead != nil {
            result.append(.entityPhrase(lead: lead, text: text, badge: badge, trail: nil, url: url))
        } else {
            result.append(token)
        }
        index += 1
    }

    return result
}

private func mergedTrailingPunctuationTokens(_ tokens: [RichReviewFlowToken]) -> [RichReviewFlowToken] {
    var result: [RichReviewFlowToken] = []

    for token in tokens {
        guard case let .text(value) = token,
              let split = splitLeadingPunctuation(in: value),
              let previous = result.popLast() else {
            result.append(token)
            continue
        }

        result.append(appendingReviewSuffix(split.punctuation, to: previous))
        if !split.remainder.isEmpty {
            result.append(.text(split.remainder))
        }
    }

    return result
}

private func splitTrailingEntityLead(in text: String) -> (prefix: String, lead: String)? {
    let pattern = #"(.*?)(\s+(?:and|or|via|on|in|a|an|the)\s*)$"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
        return nil
    }

    let nsRange = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
          match.numberOfRanges == 3,
          let prefixRange = Range(match.range(at: 1), in: text),
          let leadRange = Range(match.range(at: 2), in: text) else {
        return nil
    }

    let prefix = String(text[prefixRange])
    let lead = String(text[leadRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !lead.isEmpty else { return nil }
    return (prefix, lead)
}

private func splitLeadingEntityTrail(in text: String) -> (trail: String, remainder: String)? {
    let allowedPunctuation = CharacterSet(charactersIn: "-'’/&")
    let blockedFirstWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "did", "do", "does",
        "for", "from", "in", "into", "is", "it", "of", "on", "or", "so", "that",
        "the", "their", "then", "these", "this", "those", "to", "via", "was", "were",
        "with"
    ]

    var cursor = text.startIndex
    while cursor < text.endIndex, text[cursor].isWhitespace {
        cursor = text.index(after: cursor)
    }

    guard cursor < text.endIndex else { return nil }

    func readWord(from start: String.Index) -> (word: String, end: String.Index)? {
        var end = start
        while end < text.endIndex {
            let character = text[end]
            if character.isLetter || character.isNumber {
                end = text.index(after: end)
                continue
            }

            if let scalar = character.unicodeScalars.first,
               allowedPunctuation.contains(scalar) {
                end = text.index(after: end)
                continue
            }

            break
        }

        guard end > start else { return nil }
        return (String(text[start..<end]), end)
    }

    guard let first = readWord(from: cursor) else { return nil }
    guard !blockedFirstWords.contains(first.word.lowercased()) else { return nil }

    var trailEnd = first.end
    var nextCursor = trailEnd
    while nextCursor < text.endIndex, text[nextCursor].isWhitespace {
        nextCursor = text.index(after: nextCursor)
    }

    if nextCursor < text.endIndex,
       let second = readWord(from: nextCursor),
       !blockedFirstWords.contains(second.word.lowercased()) {
        trailEnd = second.end
    }

    let trail = String(text[cursor..<trailEnd])
    guard !trail.isEmpty else { return nil }
    return (trail, String(text[trailEnd...]))
}

private func splitLeadingPunctuation(in text: String) -> (punctuation: String, remainder: String)? {
    let punctuationCharacters = CharacterSet(charactersIn: ",.;:!?)]}\"”’")
    var cursor = text.startIndex

    while cursor < text.endIndex,
          let scalar = text[cursor].unicodeScalars.first,
          punctuationCharacters.contains(scalar) {
        cursor = text.index(after: cursor)
    }

    guard cursor > text.startIndex else { return nil }
    return (String(text[..<cursor]), String(text[cursor...]))
}

private func appendingReviewSuffix(_ suffix: String, to token: RichReviewFlowToken) -> RichReviewFlowToken {
    switch token {
    case let .text(value):
        return .text(value + suffix)
    case let .strong(value):
        return .strong(value + suffix)
    case let .emphasis(value, url):
        return .emphasis(value + suffix, url: url)
    case let .code(value, url):
        return .code(value + suffix, url: url)
    case let .link(value, url):
        return .link(value + suffix, url: url)
    case let .entity(text, badge, url):
        return .entity(text: text + suffix, badge: badge, url: url)
    case let .entityPhrase(lead, text, badge, trail, url):
        if let trail, !trail.isEmpty {
            return .entityPhrase(lead: lead, text: text, badge: badge, trail: trail + suffix, url: url)
        }
        return .entityPhrase(
            lead: lead,
            text: text,
            badge: badge.map { SourceBadgeModel(label: $0.label + suffix, icon: $0.icon) },
            trail: nil,
            url: url
        )
    }
}

private struct InlineToken: Identifiable {
    enum Kind {
        case text(String)
        case strong(String)
        case emphasis(String)
        case code(String)
        case highlight(String)
        case link(text: String, url: String)
        case badge(SourceBadgeModel)
    }

    let id = UUID()
    let kind: Kind
}

private enum MarkdownInlineParser {
    private struct Segment {
        enum Kind {
            case text
            case strong
            case emphasis
            case code
            case highlight
            case link(String)
            case badge(SourceBadgeModel)
        }

        let kind: Kind
        let text: String
    }

    static func tokens(from markdown: String, inferBadges: Bool) -> [InlineToken] {
        parseSegments(markdown).flatMap { segment in
            tokens(from: segment, inferBadges: inferBadges)
        }
    }

    private static func tokens(from segment: Segment, inferBadges: Bool) -> [InlineToken] {
        let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)

        if case let .badge(badge) = segment.kind {
            return [InlineToken(kind: .badge(badge))]
        }

        if inferBadges {
            switch segment.kind {
            case .text, .link:
                break
            case .badge:
                break
            default:
                if let badge = SourceBadgeFactory.inlineBadge(for: trimmed) {
                    return [InlineToken(kind: .badge(badge))]
                }
            }
        }

        if case let .link(url) = segment.kind {
            return [InlineToken(kind: .link(text: trimmed, url: url))]
        }

        if !inferBadges {
            if case .text = segment.kind,
               !segment.text.isEmpty,
               trimmed.isEmpty {
                return [InlineToken(kind: .text(segment.text))]
            }

            let chunks = preservedInlineChunks(from: segment.text)

            switch segment.kind {
            case .text:
                return chunks.map { InlineToken(kind: .text($0)) }
            case .strong:
                return chunks.map { InlineToken(kind: .strong($0)) }
            case .emphasis:
                return chunks.map { InlineToken(kind: .emphasis($0)) }
            case .code:
                return [InlineToken(kind: .code(trimmed))]
            case .highlight:
                return [InlineToken(kind: .highlight(trimmed))]
            case .link:
                return [InlineToken(kind: .text(trimmed))]
            case let .badge(badge):
                return [InlineToken(kind: .badge(badge))]
            }
        }

        let words = segment.text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard !words.isEmpty else { return [] }

        switch segment.kind {
        case .text:
            return inferBadges ? badgeAwareTextTokens(from: words) : words.map { InlineToken(kind: .text($0)) }
        case .strong:
            return words.map { InlineToken(kind: .strong($0)) }
        case .emphasis:
            return words.map { InlineToken(kind: .emphasis($0)) }
        case .code:
            return [InlineToken(kind: .code(trimmed))]
        case .highlight:
            return [InlineToken(kind: .highlight(trimmed))]
        case .link:
            return [InlineToken(kind: .text(trimmed))]
        case let .badge(badge):
            return [InlineToken(kind: .badge(badge))]
        }
    }

    private static func badgeAwareTextTokens(from words: [String]) -> [InlineToken] {
        var tokens: [InlineToken] = []
        var index = 0

        while index < words.count {
            var matchedBadge: SourceBadgeModel?
            var matchedWordCount = 0

            for candidateLength in stride(from: min(3, words.count - index), through: 1, by: -1) {
                let candidate = words[index..<(index + candidateLength)].joined(separator: " ")
                let cleaned = cleanedBadgeCandidate(candidate)
                guard !cleaned.isEmpty else { continue }
                if let badge = SourceBadgeFactory.inlineBadge(for: cleaned) {
                    matchedBadge = badge
                    matchedWordCount = candidateLength
                    break
                }
            }

            if let matchedBadge, matchedWordCount > 0 {
                tokens.append(InlineToken(kind: .badge(matchedBadge)))
                index += matchedWordCount
            } else {
                tokens.append(InlineToken(kind: .text(words[index])))
                index += 1
            }
        }

        return tokens
    }

    private static func cleanedBadgeCandidate(_ value: String) -> String {
        let allowedBadgeCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".+-_"))
        return value.trimmingCharacters(in: allowedBadgeCharacters.inverted.union(.whitespacesAndNewlines))
    }

    private static func preservedInlineChunks(from value: String) -> [String] {
        guard !value.isEmpty else { return [] }

        var chunks: [String] = []
        var currentChunk = ""

        for character in value {
            currentChunk.append(character)

            if character.isWhitespace, !currentChunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chunks.append(currentChunk)
                currentChunk = ""
            }
        }

        if !currentChunk.isEmpty {
            if currentChunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !chunks.isEmpty {
                chunks[chunks.count - 1].append(currentChunk)
            } else {
                chunks.append(currentChunk)
            }
        }

        return chunks
    }

    private static func parseSegments(_ markdown: String) -> [Segment] {
        var segments: [Segment] = []
        var index = markdown.startIndex

        while index < markdown.endIndex {
            if let (badge, endIndex) = parseAppTag(in: markdown, from: index) {
                segments.append(Segment(kind: .badge(badge), text: badge.label))
                index = endIndex
                continue
            }

            if markdown[index] == "[",
               let labelClose = markdown[index...].firstIndex(of: "]"),
               markdown.index(after: labelClose) < markdown.endIndex,
               markdown[markdown.index(after: labelClose)] == "(",
               let urlClose = markdown[markdown.index(labelClose, offsetBy: 2)...].firstIndex(of: ")") {
                let labelStart = markdown.index(after: index)
                let urlStart = markdown.index(labelClose, offsetBy: 2)
                let label = String(markdown[labelStart..<labelClose])
                let url = String(markdown[urlStart..<urlClose]).trimmingCharacters(in: .whitespacesAndNewlines)
                segments.append(Segment(kind: .link(url), text: label))
                index = markdown.index(after: urlClose)
                continue
            }

            if markdown[index...].hasPrefix("=="),
               let closing = markdown[markdown.index(index, offsetBy: 2)...].range(of: "==") {
                let start = markdown.index(index, offsetBy: 2)
                segments.append(Segment(kind: .highlight, text: String(markdown[start..<closing.lowerBound])))
                index = closing.upperBound
                continue
            }

            if markdown[index...].hasPrefix("**`"),
               let closing = markdown[markdown.index(index, offsetBy: 3)...].range(of: "`**") {
                let start = markdown.index(index, offsetBy: 3)
                segments.append(Segment(kind: .code, text: String(markdown[start..<closing.lowerBound])))
                index = closing.upperBound
                continue
            }

            if markdown[index...].hasPrefix("**"),
               let closing = markdown[markdown.index(index, offsetBy: 2)...].range(of: "**") {
                let start = markdown.index(index, offsetBy: 2)
                segments.append(Segment(kind: .strong, text: String(markdown[start..<closing.lowerBound])))
                index = closing.upperBound
                continue
            }

            if markdown[index] == "`",
               let closing = markdown[markdown.index(after: index)...].firstIndex(of: "`") {
                let start = markdown.index(after: index)
                segments.append(Segment(kind: .code, text: String(markdown[start..<closing])))
                index = markdown.index(after: closing)
                continue
            }

            if markdown[index] == "*",
               let closing = markdown[markdown.index(after: index)...].firstIndex(of: "*") {
                let start = markdown.index(after: index)
                segments.append(Segment(kind: .emphasis, text: String(markdown[start..<closing])))
                index = markdown.index(after: closing)
                continue
            }

            let nextIndex = nextMarkerIndex(in: markdown, from: index) ?? markdown.endIndex
            segments.append(Segment(kind: .text, text: String(markdown[index..<nextIndex])))
            index = nextIndex
        }

        return segments
    }

    private static func nextMarkerIndex(in markdown: String, from index: String.Index) -> String.Index? {
        let remaining = markdown[index...]
        let candidates = [
            remaining.range(of: "<app", options: [.caseInsensitive])?.lowerBound,
            remaining.firstIndex(of: "["),
            remaining.range(of: "==")?.lowerBound,
            remaining.range(of: "**`")?.lowerBound,
            remaining.range(of: "**")?.lowerBound,
            remaining.firstIndex(of: "`"),
            remaining.firstIndex(of: "*"),
        ].compactMap { $0 }

        return candidates.min()
    }

    private static func parseAppTag(
        in markdown: String,
        from index: String.Index
    ) -> (SourceBadgeModel, String.Index)? {
        guard markdown[index] == "<",
              let openTagEnd = markdown[index...].firstIndex(of: ">") else {
            return nil
        }

        let openTag = String(markdown[index...openTagEnd])
        guard openTag.range(of: #"^<app\b"#, options: [.regularExpression, .caseInsensitive]) != nil,
              let refMatch = openTag.range(
                  of: #"id\s*=\s*["']([^"']+)["']"#,
                  options: [.regularExpression, .caseInsensitive]
              ) else {
            return nil
        }

        let contentStart = markdown.index(after: openTagEnd)
        guard let contentEnd = markdown[contentStart...].range(of: "</app>", options: [.caseInsensitive])?.lowerBound else {
            return nil
        }

        let refText = String(openTag[refMatch])
        let referenceID = refText
            .replacingOccurrences(
                of: #"^.*?["']([^"']+)["'].*$"#,
                with: "$1",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let label = String(markdown[contentStart..<contentEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !label.isEmpty else { return nil }

        let badge = SourceBadgeFactory.inlineBadge(for: label)
            ?? SourceBadgeFactory.inlineBadge(for: referenceID)
            ?? SourceBadgeModel(label: label, icon: .none)
        let endIndex = markdown.index(contentEnd, offsetBy: "</app>".count)
        return (badge, endIndex)
    }
}

private enum MarkdownHighlightParser {
    struct Segment {
        let text: String
        let isHighlight: Bool
    }

    static func attributedSegments(from markdown: String) -> [Segment] {
        var segments: [Segment] = []
        var index = markdown.startIndex

        while index < markdown.endIndex {
            if markdown[index...].hasPrefix("=="),
               let closing = markdown[markdown.index(index, offsetBy: 2)...].range(of: "==") {
                let start = markdown.index(index, offsetBy: 2)
                segments.append(Segment(text: String(markdown[start..<closing.lowerBound]), isHighlight: true))
                index = closing.upperBound
                continue
            }

            let nextIndex = markdown[index...].range(of: "==")?.lowerBound ?? markdown.endIndex
            segments.append(Segment(text: String(markdown[index..<nextIndex]), isHighlight: false))
            index = nextIndex
        }

        return segments
    }
}
