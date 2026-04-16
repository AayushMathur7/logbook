import DriftlyCore
import SwiftUI

struct SettingsSheet: View {
    private struct ModelOption: Identifiable {
        let label: String
        let value: String
        let detail: String?

        var id: String { value.isEmpty ? label : value }
    }

    private let codexModelOptions: [ModelOption] = [
        ModelOption(label: "GPT-5.4", value: "gpt-5.4", detail: "Recommended default. OpenAI’s flagship model for complex reasoning and coding."),
        ModelOption(label: "GPT-5.4 mini", value: "gpt-5.4-mini", detail: "Lower-latency GPT-5.4 variant for coding and subagents."),
        ModelOption(label: "GPT-5.4 nano", value: "gpt-5.4-nano", detail: "Cheapest GPT-5.4-class option for simple high-volume tasks."),
        ModelOption(label: "codex-mini-latest", value: "codex-mini-latest", detail: "Fast reasoning model optimized specifically for Codex CLI."),
    ]

    private let claudeModelOptions: [ModelOption] = [
        ModelOption(label: "Opus", value: "opus", detail: "Recommended default. Anthropic’s most capable model alias in Claude Code."),
        ModelOption(label: "Sonnet", value: "sonnet", detail: "Latest Sonnet model, currently Sonnet 4."),
        ModelOption(label: "Haiku", value: "haiku", detail: "Fast and efficient Haiku model for simple tasks."),
        ModelOption(label: "Sonnet 1M", value: "sonnet[1m]", detail: "Latest Sonnet model with a 1M token context window."),
        ModelOption(label: "Opus Plan", value: "opusplan", detail: "Uses Opus in plan mode, then Sonnet for execution."),
    ]

    private let weekdayOptions: [(value: Int, label: String)] = [
        (1, "Sunday"),
        (2, "Monday"),
        (3, "Tuesday"),
        (4, "Wednesday"),
        (5, "Thursday"),
        (6, "Friday"),
        (7, "Saturday"),
    ]

    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DriftlyStyle.canvasBottom
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Text("Settings")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    settingsChromeButton("Done") {
                        model.saveCaptureSettings()
                        dismiss()
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        settingsSection("AI review") {
                            Text("Pick how Driftly writes reviews. Codex is the default. Claude Code is the other option.")
                                .font(.system(size: 11))
                                .foregroundStyle(DriftlyStyle.subtleText)
                                .fixedSize(horizontal: false, vertical: true)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Provider")
                                    .font(.system(size: 12, weight: .medium))
                                Menu {
                                    ForEach(AIReviewProvider.visibleAppCases, id: \.rawValue) { provider in
                                        Button(provider.displayName) {
                                            model.reviewProviderSelection = provider
                                            Task { await model.refreshReviewProviderStatus() }
                                        }
                                    }
                                } label: {
                                    settingsMenuField(model.reviewProviderSelection.displayName)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            switch model.reviewProviderSelection {
                            case .codex:
                                chatCLISetupOverview(
                                    selectedTool: .codex,
                                    selectedStatus: model.codexCLIStatus
                                )

                                VStack(alignment: .leading, spacing: 8) {
                                    settingsModelDropdown(
                                        title: "Model",
                                        selection: $model.codexModelName,
                                        options: codexModelOptions
                                    )
                                }

                                HStack(spacing: 8) {
                                    settingsTextField(title: "Timeout", text: $model.chatCLITimeoutInput)
                                        .frame(width: 92)

                                    Spacer(minLength: 0)

                                    settingsChromeButton("Open guide") {
                                        model.openChatCLIInstallGuide(for: .codex)
                                    }

                                    if !model.codexCLIStatus.authenticated {
                                        settingsChromeButton("Sign in") {
                                            model.openChatCLILogin(for: .codex)
                                        }
                                    }

                                    settingsChromeButton("Refresh") {
                                        Task { await model.refreshReviewProviderStatus() }
                                    }
                                }

                                settingsInlineToggle("Debug model I/O", isOn: $model.chatCLIStoreDebugIO)
                            case .claude:
                                chatCLISetupOverview(
                                    selectedTool: .claude,
                                    selectedStatus: model.claudeCLIStatus
                                )

                                VStack(alignment: .leading, spacing: 8) {
                                    settingsModelDropdown(
                                        title: "Model",
                                        selection: $model.claudeModelName,
                                        options: claudeModelOptions
                                    )
                                }

                                HStack(spacing: 8) {
                                    settingsTextField(title: "Timeout", text: $model.chatCLITimeoutInput)
                                        .frame(width: 92)

                                    Spacer(minLength: 0)

                                    settingsChromeButton("Open guide") {
                                        model.openChatCLIInstallGuide(for: .claude)
                                    }

                                    if !model.claudeCLIStatus.authenticated {
                                        settingsChromeButton("Sign in") {
                                            model.openChatCLILogin(for: .claude)
                                        }
                                    }

                                    settingsChromeButton("Refresh") {
                                        Task { await model.refreshReviewProviderStatus() }
                                    }
                                }

                                settingsInlineToggle("Debug model I/O", isOn: $model.chatCLIStoreDebugIO)
                            }

                            if !model.reviewProviderStatusMessage.isEmpty {
                                settingsStatusMessage(
                                    text: model.reviewProviderStatusMessage,
                                    isError: model.reviewProviderStatusIsError
                                )
                            }
                        }

                        settingsSection("Capture") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Nudges")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Send a quiet notification when Driftly sees clear drift during a session.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(DriftlyStyle.subtleText)
                                    .fixedSize(horizontal: false, vertical: true)

                                captureToggleRow(
                                    title: "Enable nudges",
                                    detail: "Uses the default cadence: waits a bit at the start, stays quiet unless drift looks clear, and sends only occasional recovery nudges.",
                                    isOn: Binding(
                                        get: { model.focusGuardEnabled },
                                        set: { model.setNudgesEnabled($0) }
                                    )
                                )

                                Text("Nudges use only local session signals and stay conservative when the evidence is mixed.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(DriftlyStyle.subtleText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            captureToggleRow(
                                title: "Window titles",
                                detail: "Capture editor titles, browser page titles, and active document names when macOS allows it.",
                                isOn: $model.trackAccessibilityTitles
                            )
                            captureToggleRow(
                                title: "Browser context",
                                detail: "Capture page titles, domains, and URLs from supported browsers.",
                                isOn: $model.trackBrowserContext
                            )
                            captureToggleRow(
                                title: "Finder context",
                                detail: "Capture the current Finder folder when Finder is frontmost.",
                                isOn: $model.trackFinderContext
                            )
                            captureToggleRow(
                                title: "Shell commands",
                                detail: "Import terminal commands through the shell integration.",
                                isOn: $model.trackShellCommands
                            )
                            captureToggleRow(
                                title: "File activity",
                                detail: "Capture file changes under the watched paths that Driftly observes.",
                                isOn: $model.trackFileSystemActivity
                            )
                            captureToggleRow(
                                title: "Clipboard",
                                detail: "Capture short clipboard previews when the clipboard changes.",
                                isOn: $model.trackClipboard
                            )
                            captureToggleRow(
                                title: "Presence",
                                detail: "Capture idle, resume, wake, and sleep signals to explain pauses in the block.",
                                isOn: $model.trackPresence
                            )

                            HStack(spacing: 8) {
                                Text("Retention")
                                    .font(.system(size: 12, weight: .medium))
                                Spacer()
                                settingsTextField(title: "Days", text: $model.rawEventRetentionDaysInput)
                                    .frame(width: 80)
                            }

                            Text("Nudges use only local session signals and keep the cadence internal so the product stays simple.")
                                .font(.system(size: 11))
                                .foregroundStyle(DriftlyStyle.subtleText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        settingsSection("Summaries") {
                            Text("Auto-write a short daily or weekly pattern summary from your saved sessions.")
                                .font(.system(size: 11))
                                .foregroundStyle(DriftlyStyle.subtleText)
                                .fixedSize(horizontal: false, vertical: true)

                            summaryScheduleBlock(
                                title: "Daily",
                                detail: "Generate one daily summary after the time you pick.",
                                isOn: $model.dailySummaryEnabled
                            ) {
                                HStack(spacing: 6) {
                                    Text("Every day at")
                                        .font(.system(size: 11))
                                        .foregroundStyle(DriftlyStyle.subtleText)
                                    summaryTimeMenu(selection: $model.dailySummaryTime)
                                }
                            }

                            summaryScheduleBlock(
                                title: "Weekly",
                                detail: "Generate one weekly summary for the selected weekday and time.",
                                isOn: $model.weeklySummaryEnabled
                            ) {
                                HStack(spacing: 8) {
                                    Text("Every")
                                        .font(.system(size: 11))
                                        .foregroundStyle(DriftlyStyle.subtleText)
                                    Menu {
                                        ForEach(weekdayOptions, id: \.value) { option in
                                            Button(option.label) {
                                                model.weeklySummaryWeekday = option.value
                                            }
                                        }
                                    } label: {
                                        summarySelectionPill(
                                            weekdayOptions.first(where: { $0.value == model.weeklySummaryWeekday })?.label ?? "Sunday"
                                        )
                                    }
                                    .frame(width: 112)

                                    Text("at")
                                        .font(.system(size: 11))
                                        .foregroundStyle(DriftlyStyle.subtleText)
                                    summaryTimeMenu(selection: $model.weeklySummaryTime)
                                }
                            }

                            summaryDetailRow(
                                title: "Notify when ready",
                                detail: "Send a notification after a daily or weekly summary is written.",
                                isOn: $model.summaryNotifyWhenReady
                            )
                        }

                        settingsSection("Permissions") {
                            permissionRow(
                                title: "Accessibility",
                                subtitle: model.accessibilityTrusted
                                    ? "Enabled"
                                    : "Needed for window titles, browser page titles, and richer session context.",
                                actionTitle: model.accessibilityTrusted ? "Open pane" : "Open System Settings"
                            ) {
                                model.requestAccessibilityAccess()
                            }
                        }

                        settingsSection("Privacy") {
                            Text("Driftly stays local. It captures app, title, browser, shell, file, clipboard preview, and presence signals only when those sources are enabled. It does not capture screenshots, OCR, audio, camera, microphone, or keystrokes.")
                                .font(.system(size: 11))
                                .foregroundStyle(DriftlyStyle.subtleText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack(spacing: 8) {
                            settingsChromeButton("Save") {
                                model.saveCaptureSettings()
                                dismiss()
                            }

                            settingsChromeButton("Clear events") {
                                model.clearAllEvents()
                            }

                            settingsChromeButton("Clear debug") {
                                model.clearModelDebugData()
                            }
                        }

                        if let errorMessage = model.errorMessage, !errorMessage.isEmpty {
                            InlineMessage(text: errorMessage, tint: DriftlyStyle.warning)
                        }
                    }
                    .padding(.bottom, 12)
                    .textSelection(.enabled)
                }
            }
            .padding(16)
        }
        .frame(width: 480, height: 420)
        .background(DriftlyStyle.canvasBottom)
        .preferredColorScheme(.dark)
        .task {
            await model.refreshAvailableModels()
        }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DriftlyStyle.subtleText)
            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            Divider()
                .overlay(DriftlyStyle.cardStroke.opacity(0.75))
                .padding(.top, 2)
        }
    }

    private func permissionRow(title: String, subtitle: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(DriftlyStyle.subtleText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            settingsChromeButton(actionTitle, action: action)
        }
    }

    private func settingsTextField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
            TextField(title, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DriftlyStyle.inputFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DriftlyStyle.cardStroke, lineWidth: 1)
                )
        }
    }

    private func captureToggleRow(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(DriftlyStyle.subtleText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            settingsSwitch(isOn: isOn)
        }
    }

    private func summaryScheduleBlock<Controls: View>(
        title: String,
        detail: String,
        isOn: Binding<Bool>,
        @ViewBuilder controls: () -> Controls
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(DriftlyStyle.subtleText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                settingsSwitch(isOn: isOn)
            }

            if isOn.wrappedValue {
                controls()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DriftlyStyle.inputFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DriftlyStyle.cardStroke, lineWidth: 1)
        )
    }

    private func summaryDetailRow(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(DriftlyStyle.subtleText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            settingsSwitch(isOn: isOn)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DriftlyStyle.inputFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DriftlyStyle.cardStroke, lineWidth: 1)
        )
    }

    private func chatCLISetupOverview(selectedTool: ChatCLITool, selectedStatus: ChatCLIStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("You only need one CLI installed and signed in on this Mac.")
                .font(.system(size: 11))
                .foregroundStyle(DriftlyStyle.subtleText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 10) {
                chatCLIStatusCard(
                    tool: .codex,
                    status: model.codexCLIStatus,
                    isSelected: selectedTool == .codex
                )
                chatCLIStatusCard(
                    tool: .claude,
                    status: model.claudeCLIStatus,
                    isSelected: selectedTool == .claude
                )
            }

            Text(selectedStatus.authenticated
                 ? "Signed-in CLI detected. Pick a preset model if you want, or leave it on the default."
                 : "If the CLI is already installed, sign in once from Terminal, then hit Refresh here.")
                .font(.system(size: 11))
                .foregroundStyle(DriftlyStyle.subtleText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chatCLIStatusCard(tool: ChatCLITool, status: ChatCLIStatus, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 6) {
                Text(tool.displayName)
                    .font(.system(size: 12, weight: .medium))
                if isSelected {
                    Text("Selected")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DriftlyStyle.accent)
                }
            }

            Text(chatCLIStatusLabel(for: status))
                .font(.system(size: 11))
                .foregroundStyle(status.authenticated ? DriftlyStyle.subtleText : DriftlyStyle.warning)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                settingsChromeButton(status.installed ? "Guide" : "Install") {
                    model.openChatCLIInstallGuide(for: tool)
                }

                if status.installed && !status.authenticated {
                    settingsChromeButton("Sign in") {
                        model.openChatCLILogin(for: tool)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? DriftlyStyle.badgeFill.opacity(0.9) : DriftlyStyle.inputFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? DriftlyStyle.badgeStroke : DriftlyStyle.cardStroke, lineWidth: 1)
        )
    }

    private func chatCLIStatusLabel(for status: ChatCLIStatus) -> String {
        if status.authenticated {
            return "Installed and signed in"
        }
        if status.installed {
            return "Installed, but not signed in"
        }
        return "Not installed yet"
    }

    private func settingsStatusMessage(text: String, isError: Bool) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(isError ? DriftlyStyle.warning : DriftlyStyle.subtleText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func settingsModelDropdown(title: String, selection: Binding<String>, options: [ModelOption]) -> some View {
        let selectedValue = selection.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedOption = options.first(where: { $0.value == selectedValue })

        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))

            Menu {
                ForEach(options) { option in
                    Button {
                        selection.wrappedValue = option.value
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label)
                            if let detail = option.detail, !detail.isEmpty {
                                Text(detail)
                            }
                        }
                    }
                }
            } label: {
                settingsMenuField(selectedOption?.label ?? (selectedValue.isEmpty ? "Default" : selectedValue))
            }

            if let detail = selectedOption?.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(DriftlyStyle.subtleText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !selectedValue.isEmpty {
                Text("Using custom model id: \(selectedValue)")
                    .font(.system(size: 11))
                    .foregroundStyle(DriftlyStyle.subtleText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func settingsMenuField(_ value: String) -> some View {
        HStack(spacing: 8) {
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(DriftlyStyle.text)
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DriftlyStyle.subtleText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DriftlyStyle.inputFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DriftlyStyle.cardStroke, lineWidth: 1)
        )
    }

    private func settingsChromeButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(DriftlyStyle.badgeFill)
            )
            .overlay(
                Capsule()
                    .stroke(DriftlyStyle.cardStroke, lineWidth: 1)
            )
            .buttonStyle(.plain)
    }

    private func summaryTimeMenu(selection: Binding<Date>) -> some View {
        Menu {
            ForEach(summaryTimeOptions, id: \.self) { option in
                Button(summaryTimeLabel(for: option)) {
                    selection.wrappedValue = option
                }
            }
        } label: {
            summarySelectionPill(summaryTimeLabel(for: selection.wrappedValue))
        }
        .frame(width: 96)
    }

    private func summarySelectionPill(_ value: String) -> some View {
        HStack(spacing: 8) {
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(DriftlyStyle.text)
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DriftlyStyle.subtleText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DriftlyStyle.inputFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DriftlyStyle.cardStroke, lineWidth: 1)
        )
    }

    private func settingsInlineToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 8) {
                settingsSwitch(isOn: isOn)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(DriftlyStyle.subtleText)
            }
        }
        .buttonStyle(.plain)
    }

    private func settingsSwitch(isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            ZStack(alignment: isOn.wrappedValue ? .trailing : .leading) {
                Capsule()
                    .fill(isOn.wrappedValue ? DriftlyStyle.badgeFill : DriftlyStyle.inputFill)
                    .frame(width: 34, height: 20)
                    .overlay(
                        Capsule()
                            .stroke(isOn.wrappedValue ? DriftlyStyle.badgeStroke : DriftlyStyle.cardStroke, lineWidth: 1)
                    )
                Circle()
                    .fill(DriftlyStyle.text)
                    .frame(width: 14, height: 14)
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
    }

    private var summaryTimeOptions: [Date] {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: Date())

        return stride(from: 0, through: 23 * 60 + 50, by: 10).compactMap { minuteOffset in
            calendar.date(byAdding: .minute, value: minuteOffset, to: base)
        }
    }

    private func summaryTimeLabel(for date: Date) -> String {
        ActivityFormatting.shortTime.string(from: date)
    }
}
