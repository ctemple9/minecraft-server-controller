---
description: Execute the next prompt from the MSC audit flowstate roadmap
---

You are executing one step of the MSC audit roadmap. The user should not have to paste
anything — the documents contain everything you need.

**Master execution doc:** /Users/camerontemple/Desktop/flowstate.md
**Audit (source of truth):** /Users/camerontemple/Desktop/improvements.md
**Repo:** /Users/camerontemple/Documents/Swift Projects/minecraft-server-controller

Follow these steps exactly:

1. Read BOTH documents fully. The rules in flowstate §1 are binding (verify against real
   code first, don't assume the audit is current, pbxproj files are registered by hand,
   SwiftUI presentation rules, Docker hide-don't-delete, one prompt = one commit).

2. Select the prompt to run:
   - If the user passed an argument ("$ARGUMENTS", e.g. "1.2"), run that prompt.
   - Otherwise, use the "Next recommended prompt" from the NEWEST Rolling Log entry in
     flowstate §7, cross-checked against the tracker (never re-run an item marked [x]
     or [–]; if the recommended prompt is already done, pick the next unstarted prompt
     in phase order).

3. Check before executing:
   - Phase gates (e.g. Prompt 5.1 is hard-gated on Phase 2 completion).
   - The prompt's own preconditions (e.g. 2.2 requires the test target from 2.1).
   - Human-in-loop flags (3.1 needs Apple credentials; 6.4 is a decision gate). If the
     prompt is blocked, explain exactly what the human must do, mark it [B] in the
     tracker with a note, and stop.
   - The prompt's model recommendation. State it. If you have reason to believe you are
     a substantially weaker model than recommended (the recs are in each prompt header),
     say so and ask the user whether to proceed before changing any files.

4. Execute the prompt's fenced text verbatim as your task. That text already requires
   you to inspect the current code before changing it and to correct improvements.md if
   reality disagrees with the audit.

5. Verify against the prompt's "Done when" criteria. Build commands and scheme names are
   in flowstate §1.3. Never mark an item [x] without verification — use [V] and say what
   remains unverified.

6. Update /Users/camerontemple/Desktop/flowstate.md: tick/annotate the tracker, and
   append a Rolling Log entry (newest at top, template in §7) recording model, changes,
   files, tests, tracker items, audit corrections, unresolved items, and the next
   recommended prompt.

7. Commit with the message the prompt specifies. Do not push unless asked.

8. End your final message with: what changed, verification status, and the next
   recommended prompt id.

Never run more than one prompt per invocation, and never run prompts in parallel — they
share the repo, the pbxproj, and flowstate.md.
