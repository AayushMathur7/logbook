import LogbookCore
import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 5) {
                Image(systemName: model.menuBarSymbolName)
                if let remaining = model.sessionRemainingLabel(now: context.date) {
                    Text(remaining)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
            }
        }
    }
}

struct MenuBarSessionView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 20) {
            titleBlock

            if let session = model.activeSession {
                activeSessionView(session: session)
            } else {
                idleView
            }

            footer
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(width: 336, alignment: .center)
        .background(LogbookStyle.canvasBottom)
    }

    private var titleBlock: some View {
        VStack(spacing: 4) {
            Text("LogBook")
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(LogbookStyle.text)

            Text(model.activeSession == nil ? "Menu bar" : "Session running")
                .font(.system(size: 11))
                .foregroundStyle(LogbookStyle.subtleText)
        }
        .frame(maxWidth: .infinity)
    }

    private func activeSessionView(session: FocusSession) -> some View {
        VStack(alignment: .center, spacing: 12) {
            Text(session.title)
                .font(.system(size: 21, weight: .semibold, design: .serif))
                .foregroundStyle(LogbookStyle.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .center, spacing: 4) {
                    Text(model.sessionRemainingLabel(now: context.date) ?? "0:00")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(LogbookStyle.text)
                        .contentTransition(.numericText())
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var idleView: some View {
        VStack(alignment: .center, spacing: 8) {
            Text("No session running")
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(LogbookStyle.text)
            Text("Start a session in the main window to see the timer and nudges here.")
                .font(.system(size: 11))
                .foregroundStyle(LogbookStyle.subtleText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                menuPrimaryButton("Open LogBook") {
                    LogbookWindowController.showMainWindow()
                }

                if model.hasRunningSession {
                    menuPrimaryButton("End session", destructive: true) {
                        model.endSessionNow()
                        LogbookWindowController.showMainWindow()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                menuTertiaryButton("Quit LogBook") {
                    LogbookWindowController.quitApp()
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity)
    }

    private func menuPrimaryButton(_ title: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(destructive ? LogbookStyle.badgeRedText : LogbookStyle.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(destructive ? LogbookStyle.badgeRedFill : LogbookStyle.badgeFill)
            )
            .overlay(
                Capsule()
                    .stroke(destructive ? LogbookStyle.badgeRedStroke : LogbookStyle.cardStroke, lineWidth: 1)
            )
            .buttonStyle(.plain)
    }

    private func menuTertiaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(LogbookStyle.subtleText)
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
            .buttonStyle(.plain)
    }
}
