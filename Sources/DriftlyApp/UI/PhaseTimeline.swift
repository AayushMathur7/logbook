import Foundation
import DriftlyCore
import SwiftUI

enum TimelinePhaseStyle {
    case focus
    case support
    case drift
    case breakState
    case neutral

    var tint: Color {
        switch self {
        case .focus:
            return DriftlyStyle.phaseFocus
        case .support:
            return DriftlyStyle.phaseSupport
        case .drift:
            return DriftlyStyle.phaseSupport
        case .breakState:
            return DriftlyStyle.phasePause
        case .neutral:
            return DriftlyStyle.phaseNeutral
        }
    }

    var label: String {
        switch self {
        case .focus:
            return "Focus"
        case .support:
            return "Support"
        case .drift:
            return "Drift"
        case .breakState:
            return "Pause"
        case .neutral:
            return "Mixed"
        }
    }
}

struct TimelineContext {
    let file: String?
    let repo: String?
}

struct TimelinePhase: Identifiable {
    let id = UUID()
    let segments: [TimelineSegment]
    let style: TimelinePhaseStyle
    let label: String
    let metadata: String
    let overlays: [AttentionOverlay]
    let sourceBadges: [SourceBadgeModel]
    let confidence: AttentionConfidence

    var startAt: Date { segments.first?.startAt ?? .now }
    var endAt: Date { segments.last?.endAt ?? startAt }
    var duration: TimeInterval { max(endAt.timeIntervalSince(startAt), 0) }
}

struct SessionPhaseTimeline: View {
    let phases: [TimelinePhase]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geometry in
                let widths = indicatorWidths(totalWidth: geometry.size.width)
                HStack(spacing: 4) {
                    ForEach(Array(phases.enumerated()), id: \.element.id) { index, phase in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(phase.style.tint)
                            .frame(width: widths[index])
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            }
            .frame(height: 10)

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(phases) { phase in
                        SessionPhaseCard(phase: phase)
                    }
                }
                .padding(.vertical, 2)
                .padding(.trailing, 12)
                .padding(.bottom, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
    }

    private func indicatorWidths(totalWidth: CGFloat) -> [CGFloat] {
        guard !phases.isEmpty else { return [] }

        let spacing = CGFloat(max(phases.count - 1, 0)) * 4
        let availableWidth = max(totalWidth - spacing, 0)
        let minimumWidth: CGFloat = 8
        let durations = phases.map { max($0.duration, 1) }
        let totalDuration = durations.reduce(0, +)

        guard totalDuration > 0, availableWidth > 0 else {
            let fallback = max((totalWidth - spacing) / CGFloat(max(phases.count, 1)), minimumWidth)
            return Array(repeating: fallback, count: phases.count)
        }

        var widths = durations.map { CGFloat($0 / totalDuration) * availableWidth }
        let undersized = widths.indices.filter { widths[$0] < minimumWidth }
        guard !undersized.isEmpty else { return widths }

        var locked = Set<Int>()
        var remainingDuration = totalDuration
        var remainingWidth = availableWidth

        for index in undersized {
            widths[index] = minimumWidth
            locked.insert(index)
            remainingDuration -= durations[index]
            remainingWidth -= minimumWidth
        }

        guard remainingDuration > 0, remainingWidth > 0 else {
            let equalWidth = max(availableWidth / CGFloat(max(phases.count, 1)), 1)
            return Array(repeating: equalWidth, count: phases.count)
        }

        for index in widths.indices where !locked.contains(index) {
            widths[index] = CGFloat(durations[index] / remainingDuration) * remainingWidth
        }

        return widths
    }
}

private struct SessionPhaseCard: View {
    let phase: TimelinePhase

    var body: some View {
        Card(secondary: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ActivityFormatting.sessionTime.string(from: phase.startAt, to: phase.endAt))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DriftlyStyle.subtleText)
                    Spacer(minLength: 8)
                }

                if !phase.sourceBadges.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(phase.sourceBadges) { badge in
                                SourceBadge(badge: badge)
                            }
                        }
                    }
                }

                TruncatedMarkdownText(
                    phase.label,
                    font: .system(size: 12, weight: .semibold),
                    color: .primary,
                    lineLimit: 3,
                    maxHeight: 48,
                    codePointSize: 11
                )
                .help(phase.label)

                if !phase.metadata.isEmpty {
                    TruncatedMarkdownText(
                        phase.metadata,
                        font: .system(size: 11),
                        color: DriftlyStyle.subtleText,
                        lineLimit: 2,
                        maxHeight: 30,
                        codePointSize: 10
                    )
                        .help(phase.metadata)
                }

                if !phase.overlays.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(phase.overlays) { overlay in
                                OverlayBadge(overlay: overlay)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: cardWidth, alignment: .leading)
    }

    private var cardWidth: CGFloat {
        min(max(CGFloat(phase.duration / 60) * 22, 156), 248)
    }
}

private struct OverlayBadge: View {
    let overlay: AttentionOverlay

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(DriftlyStyle.badgeText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DriftlyStyle.badgeFill, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(DriftlyStyle.badgeStroke, lineWidth: 1)
            )
    }

    private var label: String {
        switch overlay.kind {
        case .audio:
            if overlay.segment.appName.lowercased().contains("spotify"),
               overlay.segment.primaryLabel.lowercased() != "spotify" {
                return "Spotify: \(overlay.segment.primaryLabel)"
            }
            return "\(overlay.segment.appName) active"
        case .note:
            return overlay.segment.primaryLabel
        case .system:
            return overlay.segment.primaryLabel
        case .context:
            return overlay.segment.primaryLabel
        }
    }
}
