import Foundation
import LogbookCore
import SwiftUI

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
                let token = String(attributed[run.range].characters)
                attributed[run.range].foregroundColor = InlineSemanticColor.color(for: token)
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
    let spans: [SessionReviewInlineSpan]
    let fallbackMarkdown: String
    let font: Font
    let color: Color
    var codePointSize: CGFloat = 12

    init(
        spans: [SessionReviewInlineSpan],
        fallbackMarkdown: String,
        font: Font,
        color: Color = .primary,
        codePointSize: CGFloat = 12
    ) {
        self.spans = spans
        self.fallbackMarkdown = fallbackMarkdown
        self.font = font
        self.color = color
        self.codePointSize = codePointSize
    }

    var body: some View {
        if spans.isEmpty {
            MarkdownText(fallbackMarkdown, font: font, color: color, codePointSize: codePointSize)
        } else {
            InlineWrapLayout(horizontalSpacing: 4, verticalSpacing: 4) {
                ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                    RichReviewInlineSpanView(span: span, font: font, color: color, codePointSize: codePointSize)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                .fontWeight(.semibold)
                .foregroundStyle(InlineSemanticColor.color(for: value))
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

private struct RichReviewInlineSpanView: View {
    let span: SessionReviewInlineSpan
    let font: Font
    let color: Color
    let codePointSize: CGFloat

    var body: some View {
        switch span.kind {
        case .text:
            Text(span.text)
                .font(font)
                .foregroundStyle(color)
                .fixedSize()
        case .entity:
            if let badge = SourceBadgeFactory.inlineBadge(for: span.text) {
                SourceBadge(badge: badge)
                    .fixedSize()
            } else {
                Text(span.text)
                    .font(font)
                    .foregroundStyle(color)
                    .fixedSize()
            }
        case .title:
            Text(span.text)
                .font(font)
                .italic()
                .foregroundStyle(InlineSemanticColor.color(for: span.text).opacity(0.92))
                .fixedSize()
        case .goal:
            Text(span.text)
                .font(font)
                .fontWeight(.semibold)
                .foregroundStyle(color)
                .fixedSize()
        case .code, .file:
            Text(span.text)
                .font(LogbookStyle.codeFont(size: codePointSize, weight: .medium))
                .foregroundStyle(InlineSemanticColor.color(for: span.text))
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
