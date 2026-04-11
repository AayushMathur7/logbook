import Foundation

public enum AttentionDeriver {
    public static func derive(from segments: [TimelineSegment]) -> [AttentionSegment] {
        let sorted = segments.sorted { $0.startAt < $1.startAt }
        guard !sorted.isEmpty else { return [] }

        let candidates = sorted.map { segment -> Candidate in
            Candidate(
                segment: segment,
                isOverlay: isOverlayCandidate(segment),
                overlayKind: overlayKind(for: segment),
                confidence: confidence(for: segment)
            )
        }

        var foregrounds: [AttentionSegment] = []
        var deferredOverlays: [Candidate] = []

        for candidate in candidates {
            if !candidate.isOverlay {
                foregrounds.append(
                    AttentionSegment(
                        foreground: candidate.segment,
                        overlays: [],
                        confidence: candidate.confidence
                    )
                )
                continue
            }

            if let targetIndex = preferredForegroundIndex(for: candidate, in: foregrounds, allCandidates: candidates) {
                let overlay = AttentionOverlay(
                    kind: candidate.overlayKind ?? .context,
                    segment: candidate.segment,
                    confidence: candidate.confidence
                )
                foregrounds[targetIndex] = AttentionSegment(
                    id: foregrounds[targetIndex].id,
                    foreground: foregrounds[targetIndex].foreground,
                    overlays: foregrounds[targetIndex].overlays + [overlay],
                    confidence: foregrounds[targetIndex].confidence
                )
            } else {
                deferredOverlays.append(candidate)
            }
        }

        if foregrounds.isEmpty {
            return candidates.map {
                AttentionSegment(
                    foreground: $0.segment,
                    overlays: [],
                    confidence: $0.confidence
                )
            }
        }

        // If an overlay could not be assigned, keep it as a low-confidence foreground instead of losing it.
        for candidate in deferredOverlays {
            foregrounds.append(
                AttentionSegment(
                    foreground: candidate.segment,
                    overlays: [],
                    confidence: .low
                )
            )
        }

        return foregrounds.sorted { $0.foreground.startAt < $1.foreground.startAt }
    }

    private static func preferredForegroundIndex(
        for candidate: Candidate,
        in foregrounds: [AttentionSegment],
        allCandidates: [Candidate]
    ) -> Int? {
        guard !foregrounds.isEmpty else { return nil }

        let previousIndex = foregrounds.indices.last(where: {
            foregrounds[$0].foreground.startAt <= candidate.segment.startAt
        })
        let nextIndex = foregrounds.indices.first(where: {
            foregrounds[$0].foreground.startAt >= candidate.segment.endAt
        })

        let previousDistance = previousIndex.map {
            abs(candidate.segment.startAt.timeIntervalSince(foregrounds[$0].foreground.endAt))
        }
        let nextDistance = nextIndex.map {
            abs(foregrounds[$0].foreground.startAt.timeIntervalSince(candidate.segment.endAt))
        }

        let maxAttachDistance: TimeInterval = 180

        if let previousIndex, let previousDistance, previousDistance <= maxAttachDistance {
            if let nextIndex, let nextDistance, nextDistance <= maxAttachDistance {
                return previousDistance <= nextDistance ? previousIndex : nextIndex
            }
            return previousIndex
        }

        if let nextIndex, let nextDistance, nextDistance <= maxAttachDistance {
            return nextIndex
        }

        // As a fallback, attach passive audio to the nearest coding/browser foreground anywhere nearby.
        if candidate.overlayKind == .audio {
            let scored = foregrounds.enumerated().map { index, foreground in
                (
                    index: index,
                    distance: min(
                        abs(candidate.segment.startAt.timeIntervalSince(foreground.foreground.endAt)),
                        abs(foreground.foreground.startAt.timeIntervalSince(candidate.segment.endAt))
                    ),
                    weight: foreground.foreground.category == .coding || foreground.foreground.domain != nil ? 0 : 1
                )
            }
            .sorted {
                if $0.weight == $1.weight { return $0.distance < $1.distance }
                return $0.weight < $1.weight
            }

            if let best = scored.first, best.distance <= 300 {
                return best.index
            }
        }

        return nil
    }

    private static func isOverlayCandidate(_ segment: TimelineSegment) -> Bool {
        let app = segment.appName.lowercased()
        let domain = (segment.domain ?? "").lowercased()
        let primary = segment.primaryLabel.lowercased()

        if app.contains("spotify") || app.contains("music") {
            return true
        }
        if segment.category == .media && domain != "youtube.com" && domain != "youtu.be" {
            return true
        }
        if segment.appName == "Log Book" && primary.contains("break") {
            return true
        }
        return false
    }

    private static func overlayKind(for segment: TimelineSegment) -> AttentionOverlayKind? {
        let app = segment.appName.lowercased()
        let primary = segment.primaryLabel.lowercased()

        if app.contains("spotify") || app.contains("music") || segment.category == .media {
            return .audio
        }
        if segment.appName == "Log Book" && primary.contains("break") {
            return .note
        }
        if segment.category == .admin {
            return .system
        }
        return .context
    }

    private static func confidence(for segment: TimelineSegment) -> AttentionConfidence {
        if segment.filePath != nil || segment.repoName != nil || segment.domain != nil {
            return .high
        }
        if segment.confidence >= 0.75 {
            return .medium
        }
        return .low
    }
}

private struct Candidate {
    let segment: TimelineSegment
    let isOverlay: Bool
    let overlayKind: AttentionOverlayKind?
    let confidence: AttentionConfidence
}
