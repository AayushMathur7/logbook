import Foundation
import LogbookCore
import SwiftUI
import SVGView

struct MarkdownText: View {
    let markdown: String
    let font: Font
    let color: Color
    var lineLimit: Int? = nil
    var codePointSize: CGFloat = 12

    init(_ markdown: String, font: Font, color: Color = .primary, lineLimit: Int? = nil, codePointSize: CGFloat = 12) {
        self.markdown = markdown
        self.font = font
        self.color = color
        self.lineLimit = lineLimit
        self.codePointSize = codePointSize
    }

    var body: some View {
        if lineLimit != nil {
            Text(attributedMarkdown)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(lineLimit)
        } else {
            MarkdownFlowText(
                markdown: markdown,
                font: font,
                color: color,
                codePointSize: codePointSize
            )
        }
    }

    private var attributedMarkdown: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var attributed = (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)

        for run in attributed.runs {
            guard let intent = run.inlinePresentationIntent else { continue }
            if intent.contains(.code) {
                let token = String(attributed[run.range].characters)
                attributed[run.range].foregroundColor = InlineSemanticColor.color(for: token)
                attributed[run.range].backgroundColor = LogbookStyle.inlineCodeFill
                attributed[run.range].font = .system(size: codePointSize, weight: .medium, design: .monospaced)
            } else if intent.contains(.stronglyEmphasized) {
                attributed[run.range].foregroundColor = LogbookStyle.text
            } else if intent.contains(.emphasized) {
                let token = String(attributed[run.range].characters)
                attributed[run.range].foregroundColor = InlineSemanticColor.color(for: token).opacity(0.92)
            }
        }

        return attributed
    }
}

struct MarkdownFlowText: View {
    let markdown: String
    let font: Font
    let color: Color
    let codePointSize: CGFloat

    private var lines: [[InlineToken]] {
        markdown
            .components(separatedBy: .newlines)
            .map { line in
                MarkdownInlineParser.tokens(from: line)
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, tokens in
                InlineWrapLayout(horizontalSpacing: 4, verticalSpacing: 4) {
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
            InlineWrapLayout(horizontalSpacing: 4, verticalSpacing: 4) {
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
        spans.flatMap { span in
            flowTokens(for: span)
        }
    }

    private func flowTokens(for span: SessionReviewInlineSpan) -> [RichReviewFlowToken] {
        switch span.kind {
        case .text:
            return flowTokens(fromMarkdown: span.text)
        case .entity:
            return [.entity(text: span.text, badge: SourceBadgeFactory.inlineBadge(for: span.text), url: span.url)]
        case .title:
            return [.emphasis(span.text, url: span.url)]
        case .goal:
            return flowTokens(fromMarkdown: "**\(span.text)**")
        case .code, .file:
            return [.code(span.text, url: span.url)]
        }
    }

    private func flowTokens(fromMarkdown markdown: String) -> [RichReviewFlowToken] {
        MarkdownInlineParser.tokens(from: markdown).map { token in
            switch token.kind {
            case let .text(value):
                return .text(value)
            case let .strong(value):
                return .strong(value)
            case let .emphasis(value):
                return .emphasis(value, url: nil)
            case let .code(value):
                return .code(value, url: nil)
            case let .badge(badge):
                return .entity(text: badge.label, badge: badge, url: nil)
            }
        }
    }
}

private struct InlineTokenView: View {
    let token: InlineToken
    let font: Font
    let color: Color
    let codePointSize: CGFloat

    var body: some View {
        switch token.kind {
        case let .text(value):
            Text(value)
                .font(font)
                .foregroundStyle(color)
                .fixedSize()
        case let .strong(value):
            Text(value)
                .font(font)
                .foregroundStyle(LogbookStyle.text)
                .fixedSize()
        case let .emphasis(value):
            Text(value)
                .font(font)
                .italic()
                .foregroundStyle(InlineSemanticColor.color(for: value).opacity(0.92))
                .fixedSize()
        case let .code(value):
            Text(value)
                .font(LogbookStyle.codeFont(size: codePointSize, weight: .medium))
                .foregroundStyle(InlineSemanticColor.color(for: value))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(LogbookStyle.inlineCodeFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(LogbookStyle.inlineCodeStroke, lineWidth: 1)
                )
                .fixedSize()
        case let .badge(badge):
            SourceBadge(badge: badge)
                .fixedSize()
        }
    }
}

private enum RichReviewFlowToken {
    case text(String)
    case strong(String)
    case emphasis(String, url: String?)
    case code(String, url: String?)
    case entity(text: String, badge: SourceBadgeModel?, url: String?)
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
            Text(value)
                .font(font)
                .foregroundStyle(color)
                .fixedSize()
        case let .strong(value):
            Text(value)
                .font(font)
                .foregroundStyle(LogbookStyle.text)
                .fixedSize()
        case let .emphasis(value, url):
            linkedText(
                value,
                urlString: url,
                font: font,
                color: InlineSemanticColor.color(for: value).opacity(0.92),
                italic: true
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
        case let .code(value, url):
            linkedCode(value, urlString: url)
        }
    }

    @ViewBuilder
    private func linkedText(
        _ value: String,
        urlString: String?,
        font: Font,
        color: Color,
        italic: Bool = false
    ) -> some View {
        let base = Text(value)
            .font(font)
            .foregroundStyle(color)
            .underline(urlString != nil)
            .italic(italic)
            .fixedSize()

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
            .buttonStyle(.plain)
            .help(urlString)
        } else {
            view.fixedSize()
        }
    }

    @ViewBuilder
    private func linkedCode(_ value: String, urlString: String?) -> some View {
        let codeView = Text(value)
            .font(LogbookStyle.codeFont(size: codePointSize, weight: .medium))
            .foregroundStyle(InlineSemanticColor.color(for: value))
            .underline(urlString != nil)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(LogbookStyle.inlineCodeFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(LogbookStyle.inlineCodeStroke, lineWidth: 1)
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
                    .underline(isLinked)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(LogbookStyle.subtleText)
        .padding(.horizontal, isIconOnly ? 4 : 5)
        .padding(.vertical, 1.5)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(LogbookStyle.badgeFill.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(LogbookStyle.badgeStroke.opacity(0.65), lineWidth: 1)
        )
        .help(badge.label)
        .fixedSize()
    }

    private var shortLabel: String {
        if badge.label == "Log Book" {
            return "Log Book"
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
        case let .brandMonogram(value):
            ZStack {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(LogbookStyle.badgeFill.opacity(0.8))
                Text(value)
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundStyle(LogbookStyle.subtleText)
            }
            .frame(width: 11, height: 11)
        case let .system(systemName):
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(LogbookStyle.subtleText)
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
            let size = subview.sizeThatFits(.unspecified)

            if origin.x > bounds.minX, origin.x + size.width > bounds.minX + maxWidth {
                origin.x = bounds.minX
                origin.y += lineHeight + verticalSpacing
                lineHeight = 0
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
            return LogbookStyle.badgeGreenText
        }

        if lowered.contains("youtube") || lowered.contains("notion") || lowered == "x" || lowered.contains(" x ") || lowered.contains("http") || lowered.contains(".com") {
            return LogbookStyle.badgeWarmText
        }

        if lowered.contains("github") || lowered.contains("cursor") || lowered.contains("chrome") || lowered.contains("codex") || lowered.contains("/") || lowered.contains(".swift") || lowered.contains(".md") {
            return LogbookStyle.badgeBlueText
        }

        return LogbookStyle.inlineCodeText
    }
}

private struct InlineToken: Identifiable {
    enum Kind {
        case text(String)
        case strong(String)
        case emphasis(String)
        case code(String)
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
        }

        let kind: Kind
        let text: String
    }

    static func tokens(from markdown: String) -> [InlineToken] {
        parseSegments(markdown).flatMap { segment in
            tokens(from: segment)
        }
    }

    private static func tokens(from segment: Segment) -> [InlineToken] {
        let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)

        if segment.kind != .text, let badge = SourceBadgeFactory.inlineBadge(for: trimmed) {
            return [InlineToken(kind: .badge(badge))]
        }

        let words = segment.text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard !words.isEmpty else { return [] }

        switch segment.kind {
        case .text:
            return words.map { InlineToken(kind: .text($0)) }
        case .strong:
            return words.map { InlineToken(kind: .strong($0)) }
        case .emphasis:
            return words.map { InlineToken(kind: .emphasis($0)) }
        case .code:
            return [InlineToken(kind: .code(trimmed))]
        }
    }

    private static func parseSegments(_ markdown: String) -> [Segment] {
        var segments: [Segment] = []
        var index = markdown.startIndex

        while index < markdown.endIndex {
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
            remaining.range(of: "**`")?.lowerBound,
            remaining.range(of: "**")?.lowerBound,
            remaining.firstIndex(of: "`"),
            remaining.firstIndex(of: "*"),
        ].compactMap { $0 }

        return candidates.min()
    }
}
