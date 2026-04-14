import AppKit
import DriftlyCore
import SwiftUI

struct Card<Content: View>: View {
    var secondary = false
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(secondary ? DriftlyStyle.secondaryCardFill : DriftlyStyle.cardFill)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(DriftlyStyle.cardStroke, lineWidth: 1)
                    )
            )
    }
}

struct InlineMessage: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(DriftlyStyle.subtleText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct InlineActionMessage: View {
    let text: String
    let actionTitle: String
    let actionURL: URL
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(DriftlyStyle.subtleText)
                .tint(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var message: AttributedString {
        var link = AttributedString(actionTitle)
        link.link = actionURL
        link.underlineStyle = .single
        var result = link
        result.append(AttributedString(" \(text)"))
        return result
    }
}

struct ComposerInputFieldStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .font(DriftlyStyle.uiFont(size: 13, weight: .regular))
            .foregroundStyle(DriftlyStyle.inputText)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(backgroundFill)
            )
            .animation(.easeOut(duration: 0.12), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: colorScheme)
    }

    private var backgroundFill: Color {
        switch colorScheme {
        case .dark:
            return isFocused
                ? Color(nsColor: NSColor(calibratedWhite: 0.105, alpha: 1))
                : Color(nsColor: NSColor(calibratedWhite: 0.09, alpha: 1))
        default:
            return .white
        }
    }
}

extension View {
    func composerInputField(isFocused: Bool) -> some View {
        modifier(ComposerInputFieldStyle(isFocused: isFocused))
    }
}

struct ComposerTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let placeholder: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(string: text)
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.isEditable = true
        textField.isSelectable = true
        textField.usesSingleLineMode = true
        textField.lineBreakMode = .byTruncatingTail
        textField.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        textField.textColor = nsColor(from: DriftlyStyle.inputText)
        textField.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: nsColor(from: DriftlyStyle.inputPlaceholder),
                .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            ]
        )
        textField.delegate = context.coordinator
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.submit)
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        if textField.stringValue != text {
            textField.stringValue = text
        }

        textField.textColor = nsColor(from: DriftlyStyle.inputText)
        textField.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: nsColor(from: DriftlyStyle.inputPlaceholder),
                .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            ]
        )
    }

    private func nsColor(from color: Color) -> NSColor {
        NSColor(color)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String
        @Binding private var isFocused: Bool
        private let onSubmit: () -> Void

        init(text: Binding<String>, isFocused: Binding<Bool>, onSubmit: @escaping () -> Void) {
            _text = text
            _isFocused = isFocused
            self.onSubmit = onSubmit
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            isFocused = true
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            text = textField.stringValue
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            isFocused = false
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit()
                return true
            }
            return false
        }

        @objc func submit() {
            onSubmit()
        }
    }
}

struct VerdictPill: View {
    let verdict: SessionVerdict

    var body: some View {
        Text(verdict.title)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(DriftlyStyle.badgeFill, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(DriftlyStyle.badgeStroke, lineWidth: 1)
            )
            .foregroundStyle(DriftlyStyle.badgeText)
    }
}

struct MetadataLine: View {
    let markdown: String
    var lineLimit: Int? = nil

    var body: some View {
        MarkdownText(markdown, font: .system(size: 12), color: DriftlyStyle.subtleText, lineLimit: lineLimit)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct TruncatedMarkdownText: View {
    let markdown: String
    let font: Font
    let color: Color
    let lineLimit: Int
    var maxHeight: CGFloat?
    var codePointSize: CGFloat = 12

    init(_ markdown: String, font: Font, color: Color = .primary, lineLimit: Int, maxHeight: CGFloat? = nil, codePointSize: CGFloat = 12) {
        self.markdown = markdown
        self.font = font
        self.color = color
        self.lineLimit = lineLimit
        self.maxHeight = maxHeight
        self.codePointSize = codePointSize
    }

    var body: some View {
        MarkdownFlowText(
            markdown: markdown,
            font: font,
            color: color,
            codePointSize: codePointSize,
            inferBadges: false
        )
        .frame(maxHeight: maxHeight, alignment: .topLeading)
        .clipped()
    }
}
