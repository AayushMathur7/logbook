---
name: driftly-insight-writing
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
