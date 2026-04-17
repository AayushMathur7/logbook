import Foundation

enum DriftlyAgentContext {
    static let skillName = "driftly-insight-writing"

    static func codexAgentsMarkdown() -> String {
        """
        # Driftly

        Driftly writes local session reviews and periodic summaries from captured desktop evidence.

        Rules:
        - Judge each block against the user's stated goal and the visible evidence.
        - Keep the language concrete, calm, and short.
        - Do not invent titles, pages, surfaces, URLs, or timings.
        - Do not mention hidden context, prior sessions, reference files, or internal machinery.
        - For Driftly reviews and daily or weekly summaries, use the `\(skillName)` skill when it is available.
        - Learned patterns are soft context only. Current-session evidence wins.
        """
    }

    static func claudeMarkdown() -> String {
        """
        # Driftly

        Driftly writes local session reviews and periodic summaries from captured desktop evidence.

        Rules:
        - Judge each block against the user's stated goal and the visible evidence.
        - Keep the language concrete, calm, and short.
        - Do not invent titles, pages, surfaces, URLs, or timings.
        - Do not mention hidden context, prior sessions, reference files, or internal machinery.
        - For Driftly reviews and daily or weekly summaries, use the `\(skillName)` skill when it is available.
        - Learned patterns are soft context only. Current-session evidence wins.
        """
    }

    static func skillMarkdown() -> String {
        """
        ---
        name: \(skillName)
        description: Use when writing Driftly session reviews or daily and weekly summaries from captured local evidence. Helps keep the writing sharp, concrete, and personalized using recent local patterns and feedback without mentioning hidden memory.
        ---

        Use this skill only for Driftly-generated session reviews and daily or weekly summaries.
        Do not use it for UI copy, docs, marketing, or code changes.

        What this skill is for:
        - Produce sharp, human Driftly reviews.
        - Keep current-session evidence as the source of truth.
        - Use recent local patterns only to improve wording and next-step quality.

        Session review workflow:
        1. Read `references/what-driftly-tracks.md`.
        2. Read `references/output-style.md`.
        3. Read `references/recent-patterns.md` if it exists.
        4. For a session review, read the session packet files in `session/`:
           - `goal.txt`
           - `session-facts.md`
           - `timeline.md`
           - `session.json`
        5. Use `session-facts.md` and `timeline.md` to understand the shape of the block.
        6. Use `session.json` for exact labels, timings, domains, commands, titles, and allowed mentions when needed.
        7. If current evidence conflicts with recent patterns, trust the current evidence.
        8. Never mention the skill, reference files, prior sessions, hidden memory, or internal machinery in the final output.

        Decision order:
        1. Start from the stated goal.
        2. Decide what the block mostly became.
        3. Use specific surfaces, titles, or tools as evidence.
        4. Use one useful number only when it sharpens the point.
        5. End with one immediate next move.

        Writing contract:
        - `headline` names what the block became.
        - `summary` explains the session shape in plain language.
        - `insight` gives one calm next move or framing correction.
        - `entities` lists the concrete surfaces or tools that deserve pills in the UI.
        - `links` lists only observed links worth showing below the review.

        Headline rules:
        - Keep it short and plain.
        - Name the real thread, not just the open app.
        - Do not start the headline with "This stayed" or "This never".
        - Do not use fallback verdicts like "This never became coding." Name what it became instead.
        - Prefer phrases like repo work, setup thrash, feed checking, tab hopping, browser churn, spec reading, or video drift.
        - Avoid abstract nouns like alignment, fragmentation, orientation, exploration, optimization, or reconnaissance.
        - Avoid blamey phrasing like "you got pulled into" or "X dominated your time block".

        Summary rules:
        - Usually write exactly two short sentences.
        - Sentence 1 says what mostly happened.
        - Sentence 2 says what weakened it, or what still held if it stayed mostly on-task.
        - Mention one or two concrete surfaces, titles, pages, repos, files, or tools when visible.
        - Use browser site names over browser shells when site evidence is visible.
        - If Zoom, YouTube, GitHub, X, Telegram, or another named surface explains the block, do not mention Chrome or Safari.
        - Never mention browser profile labels like Default, Profile 1, WebStorage, or Chrome profile churn.
        - Do not say "file activity" unless a visible file name is the real story.
        - Do not list many apps when one thread explains the block.
        - Do not claim completion, understanding, or intent beyond the visible evidence.
        - Keep raw URLs out of the prose summary. Put them in `links` instead.
        - Include one compact numeric fact like 23%, 8 switches, 30s, or 9m.

        Insight rules:
        - Keep it to one sentence.
        - Make it usable right away.
        - Prefer a stop-and-replace move or a keep-and-cut move.
        - Name the concrete surface to close, keep, or return to when visible.
        - Avoid generic advice like "maintain focus", "refocus on the task", or "return to your main goal".
        - Do not use markdown code ticks in the insight.
        - Do not say "start the next block", "stay in Codex only", or "make one concrete step". Name the actual next move instead.

        Entity rules:
        - `entities` should be the 2 to 4 surfaces that actually mattered.
        - Prefer canonical labels like Codex, GitHub, Zoom, Telegram, YouTube, X, repo names, or visible file names.
        - Use canonical product names instead of raw hosts when the product is obvious, like Zoom instead of us02web.zoom.us.
        - Do not include browser shell noise like Chrome Default profile, WebStorage, or generic file churn labels.
        - Do not include Driftly unless Driftly itself clearly held meaningful time in the block.
        - If a known entity is visible, use its normal canonical name rather than inventing a custom reference ID.

        Anti-patterns to avoid:
        - dashboard language like "accounted for", "remained the dominant surface", or "desktop activity"
        - empty summaries like "watched YouTube videos and used Codex"
        - consultant wording like "fragmented repo orientation" or "aligned exploration"
        - overfitting to old labels when this block clearly took a different shape

        Final checks before returning:
        - The wording stays concrete, calm, and short.
        - Every named surface appears in the session evidence.
        - The summary adds information that the headline does not.
        - The insight points toward the stated goal instead of the distraction.
        - `entities` only include surfaces that actually mattered.
        - `links` only include URLs that were visibly opened during the session.
        """
    }

    static func openAIMetadataYAML() -> String {
        """
        interface:
          display_name: "Driftly Insight Writing"
          short_description: "Sharper Driftly review wording from recent local patterns and feedback."
          default_prompt: "Use this skill when writing Driftly reviews or periodic summaries."

        policy:
          allow_implicit_invocation: true
        """
    }

    static func recentPatternsMarkdown(from content: String?) -> String {
        if let content = content?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty {
            return content
        }

        return """
        # Recent Driftly patterns

        No recent learned patterns are available yet.

        ## How to use this

        - Treat this as optional soft context only.
        - Current session facts still win.
        - Do not mention this file or hidden memory in the final output.
        """
    }

    static func trackedEvidenceMarkdown() -> String {
        """
        # What Driftly tracks

        Driftly writes from local desktop evidence, not from mind-reading.

        Driftly can usually see:
        - frontmost app switches
        - window titles from Accessibility
        - browser tab titles and domains
        - inferred sites, repos, files, and surfaces
        - shell commands and working directories when shell integration is on
        - clipboard previews
        - quick notes
        - idle and resume events
        - lightweight timeline segments and surface switches

        Driftly does not directly know:
        - what the user intended unless the goal says it
        - the semantic content of a whole page beyond visible titles and labels
        - whether a page was genuinely useful unless the surface and goal make that clear
        - what code changed, what was understood, or what was completed unless the evidence strongly supports that

        Writing implications:
        - Do not overclaim.
        - Do not say the user was \"researching\", \"deploying\", \"orienting\", or \"building\" unless the visible surfaces support it.
        - Use titles, domains, repos, files, commands, and timing as evidence.
        - When the evidence is mixed, say it was mixed.
        - When the evidence is shallow, say the thread never really settled.
        """
    }

    static func outputStyleMarkdown() -> String {
        """
        # Driftly output style

        What Driftly should do:
        - Sound like a sharp human reflection, not analytics software.
        - Lead with what the block became.
        - Use plain phrases like repo study, setup, feed checking, tab hopping, spec reading, or YouTube drift.
        - Use one or two concrete surfaces that mattered.
        - Use one useful number when it sharpens the point.
        - Make the next step immediate and specific.
        - Keep the wording calm and non-dramatic.

        What Driftly should avoid:
        - dashboard phrasing like dominated your time block, accounted for, remained the dominant surface, desktop activity, time period
        - abstract phrasing like alignment, fragmentation, orientation, exploration, reconnaissance, optimization
        - generic verdicts like partially matched the building goal or your desktop activity didn't align
        - generic headlines like This stayed on..., This never..., or This never really became coding
        - empty summaries like watched YouTube videos and used Codex
        - blamey headlines like you got pulled into
        - full distracting video titles unless the goal was explicitly to watch that video
        - long app lists when one thread explains the block

        Preferred shape:
        - headline: what the block became
        - summary sentence 1: what mostly happened
        - summary sentence 2: what weakened it or what still held
        - insight: a direct next move with the concrete surface to close, keep, or return to

        Good examples:
        - "Codex held about 9 minutes, but Telegram and Zoom kept breaking the thread."
        - "Most of the block stayed on YouTube, while Codex only showed up in short checks."
        - "Close Telegram and return to the repo thread in Codex."
        """
    }
}
