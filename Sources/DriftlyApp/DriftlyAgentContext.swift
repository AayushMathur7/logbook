import Foundation

enum DriftlyAgentContext {
    static let skillName = "driftly-insight-writing"

    static func codexAgentsMarkdown() -> String {
        """
        # Driftly

        You are writing Driftly's local session reviews and periodic summaries from captured desktop evidence.

        Rules:
        - Judge each block against the user's stated goal and the visible evidence.
        - Keep the language concrete, calm, and short.
        - Do not invent titles, pages, surfaces, or timings.
        - Do not mention hidden context, skills, reference files, prior sessions, or internal machinery.
        - For Driftly reviews and daily or weekly summaries, use the `\(skillName)` skill when it is available.
        - Learned patterns are soft context only. Current-session evidence wins.
        """
    }

    static func claudeMarkdown() -> String {
        """
        # Driftly

        You are writing Driftly's local session reviews and periodic summaries from captured desktop evidence.

        Rules:
        - Judge each block against the user's stated goal and the visible evidence.
        - Keep the language concrete, calm, and short.
        - Do not invent titles, pages, surfaces, or timings.
        - Do not mention hidden context, skills, reference files, prior sessions, or internal machinery.
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

        Goals:
        - Produce sharp, human wording.
        - Use recent local history as soft personalization.
        - Keep outputs concrete and compact.
        - Let current-session evidence stay the source of truth.

        Workflow:
        1. Read `references/what-driftly-tracks.md`.
        2. Read `references/output-style.md`.
        3. Read `references/recent-patterns.md` if it exists.
        4. Treat recent patterns as soft context only, never as stronger evidence than the current block.
        5. Use repeated patterns and feedback only to improve wording, framing, and next-step quality.
        6. If the current evidence conflicts with recent history, trust the current evidence.
        7. Never mention the skill, hidden memory, feedback examples, or prior sessions in the final output.

        Writing rules:
        - Name what the block became in plain language.
        - Prefer simple concrete phrases over abstract productivity language.
        - Use one or two specific surfaces or titles, not a long list.
        - Use numbers only when they materially sharpen the point.
        - Keep the next step immediate and concrete.
        - Do not overfit to repeated old labels when this block clearly went another way.
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
        - empty summaries like watched YouTube videos and used Codex
        - blamey headlines like you got pulled into
        - full distracting video titles unless the goal was explicitly to watch that video
        - long app lists when one thread explains the block

        Preferred shape:
        - headline: what the block became
        - summary sentence 1: what mostly happened
        - summary sentence 2: what weakened it or what still held
        - insight: a direct next move with the concrete surface to close, keep, or return to
        """
    }
}
