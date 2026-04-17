import Foundation

enum DriftlyAgentContext {
    static let skillName = "driftly-insight-writing"
    static let patternSkillName = "driftly-pattern-writing"

    static func codexAgentsMarkdown() -> String {
        """
        # Driftly

        Driftly writes local session reviews and periodic summaries from captured desktop evidence.

        Rules:
        - Judge each block against the user's stated goal and the visible evidence.
        - Keep the language concrete, calm, and short.
        - Do not invent titles, pages, surfaces, URLs, or timings.
        - Do not mention hidden context, prior sessions, reference files, or internal machinery.
        - For single-session Driftly reviews, use the `\(skillName)` skill when it is available.
        - For daily or weekly pattern writing across multiple saved sessions, use the `\(patternSkillName)` skill when it is available.
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
        - For single-session Driftly reviews, use the `\(skillName)` skill when it is available.
        - For daily or weekly pattern writing across multiple saved sessions, use the `\(patternSkillName)` skill when it is available.
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
        - Stay grounded in the single review packet provided for the current block.

        Session review workflow:
        1. Read the single grounded session packet the caller points you to.
        2. Use only the evidence inside that packet.
        3. Do not explore unrelated files or look for extra context.
        4. Never mention the skill, hidden memory, or internal machinery in the final output.

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
        - Make it slightly more interpretive than the summary, not a copy of sentence 1.
        - If the summary names the visible sequence, let the headline name the state the block fell into.
        - Do not start the headline with "This stayed" or "This never".
        - Do not use fallback verdicts like "This never became coding." Name what it became instead.
        - Prefer phrases like repo work, setup thrash, feed checking, tab hopping, browser churn, spec reading, or video drift.
        - Avoid abstract nouns like alignment, fragmentation, orientation, exploration, optimization, or reconnaissance.
        - Avoid blamey phrasing like "you got pulled into" or "X dominated your time block".

        Summary rules:
        - Usually write exactly two short sentences.
        - Sentence 1 says what mostly happened.
        - Sentence 2 says what weakened it, or what still held if it stayed mostly on-task.
        - Keep each sentence compact and easy to scan.
        - Prefer a simple setup sentence, then an evidence or consequence sentence.
        - Avoid long comma-heavy sentences that try to explain the whole block at once.
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
        - Start with a concrete action verb when possible.
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

    static func patternSkillMarkdown() -> String {
        """
        ---
        name: \(patternSkillName)
        description: Use when writing Driftly daily or weekly reflections across a provided time window of saved sessions. Extracts the clearest repeated pattern in a few calm sentences instead of summarizing every block.
        ---

        Use this skill only for Driftly daily or weekly pattern writing across multiple saved sessions.
        Do not use it for single-session reviews, UI copy, docs, marketing, or code changes.

        What this skill is for:
        - Extract the clearest repeated pattern from the provided time window.
        - Write a short reflection, not a dashboard recap.
        - Stay grounded in the saved sessions the caller provides.

        Pattern-writing workflow:
        1. Read the provided timeframe facts and saved sessions.
        2. Look for what repeated, not what was merely present once.
        3. Name one main pattern, one supporting or blocking force, and one small next move.
        4. Never mention the skill, hidden memory, or internal machinery in the final output.

        Writing contract:
        - `title` names the period pattern in plain language.
        - `reflection` is 3 to 5 short sentences.

        Pattern rules:
        - Prefer repeated behavior over one-off highlights.
        - Mention specific goals, headlines, or surfaces only when they sharpen the pattern.
        - Use at most one or two concrete numbers.
        - Do not try to recap every saved session.
        - Do not sound like analytics software, a therapist, or a consultant.
        - Avoid labels like productivity summary, alignment assessment, or weekly report.
        - Keep the language plain, human, and slightly interpretive.

        Reflection rules:
        - Keep it sentence-based.
        - Sentence 1 should say what the user tends to do.
        - Sentence 2 should say why that pattern seems to happen.
        - Sentence 3 should say what helps or gets in the way.
        - Sentence 4 or 5 can say what to watch for next time.
        - Keep the whole `reflection` under 110 words.
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

    static func openAIMetadataYAML(
        displayName: String,
        shortDescription: String,
        defaultPrompt: String
    ) -> String {
        """
        interface:
          display_name: "\(displayName)"
          short_description: "\(shortDescription)"
          default_prompt: "\(defaultPrompt)"

        policy:
          allow_implicit_invocation: true
        """
    }

}
