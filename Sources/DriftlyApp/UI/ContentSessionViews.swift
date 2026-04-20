import Foundation
import DriftlyCore
import SwiftUI

extension ContentView {
    var setupView: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What are you focusing on?")
                        .font(.system(size: 22, weight: .medium, design: .serif))
                        .foregroundStyle(DriftlyStyle.text)
                        .padding(.bottom, 10)
                    TextField(
                        "Write the page, finish the deck, clear your inbox, ship the fix…",
                        text: $sessionGoalDraft
                    )
                    .textFieldStyle(.plain)
                    .font(DriftlyStyle.uiFont(size: 13, weight: .regular))
                    .foregroundStyle(DriftlyStyle.inputText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(DriftlyStyle.inputFill)
                    )
                    .onSubmit {
                        if sessionGoalIsValid {
                            startSessionFromDraft()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Duration")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DriftlyStyle.subtleText)
                        Spacer()
                        Text("\(model.sessionDurationMinutes) min")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }

                    Slider(
                        value: Binding(
                            get: { Double(model.sessionDurationMinutes) },
                            set: { model.setSessionDuration(Int($0.rounded())) }
                        ),
                        in: 5...120,
                        step: 5
                    )
                    .tint(DriftlyStyle.accent)

                    HStack {
                        Text("5m")
                        Spacer()
                        Text("45m")
                        Spacer()
                        Text("120m")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(DriftlyStyle.subtleText)
                }

                if let errorMessage = model.errorMessage, !errorMessage.isEmpty {
                    InlineMessage(text: errorMessage, tint: DriftlyStyle.warning)
                }

                Button {
                    startSessionFromDraft()
                } label: {
                    Text("Start session")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!sessionGoalIsValid)
            }
        }
        .padding(.horizontal, 12)
    }

    func runningView(session: FocusSession) -> some View {
        VStack(alignment: .center, spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .center, spacing: 22) {
                Text(session.title)
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(DriftlyStyle.subtleText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(DriftlyStyle.inputFill)
                    )
                    .overlay(
                        Capsule()
                            .stroke(DriftlyStyle.cardStroke, lineWidth: 1)
                    )

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(remainingLabel(session: session, now: context.date))
                        .font(.system(size: 64, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                        .monospacedDigit()
                }

                openAIActionButton("End session", systemImage: "stop.fill") {
                    model.endSessionNow()
                }
            }
            .frame(maxWidth: 540)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .padding(.horizontal, 12)
    }

    var generatingView: some View {
        VStack(alignment: .center, spacing: 14) {
            Spacer(minLength: 0)

            ProgressView()
                .controlSize(.large)
                .scaleEffect(1.15)

            Text("Generating review")
                .font(.system(size: 24, weight: .semibold, design: .serif))
                .multilineTextAlignment(.center)

            Text(model.evidenceStatusText)
                .font(.system(size: 12))
                .foregroundStyle(DriftlyStyle.subtleText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(.horizontal, 12)
    }

    func openAIActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(DriftlyStyle.badgeFill)
                )
                .overlay(
                    Capsule()
                        .stroke(DriftlyStyle.cardStroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    func syncSessionGoalDraftFromModel() {
        guard model.surfaceState == .setup else { return }
        if sessionGoalDraft.isEmpty {
            sessionGoalDraft = model.sessionDraftTitle
        }
    }

    var sessionGoalIsValid: Bool {
        !sessionGoalDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func startSessionFromDraft() {
        model.sessionDraftTitle = sessionGoalDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        model.startSession()
    }

    func remainingLabel(session: FocusSession, now: Date) -> String {
        let remaining = max(Int(session.endsAt.timeIntervalSince(now)), 0)
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
