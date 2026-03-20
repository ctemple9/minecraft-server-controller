# Router Port Forward Guide Maintenance Rules

This file is for maintainers of the router guide system in `MSCmacOS Swift`.

## Scope

These rules are for the structured guide system only:

- `RouterPortForwardGuidesFoundation.swift`
- `RouterPortForwardGuideCatalogLoader.swift`
- `RouterPortForwardGuideRepository.swift`
- `RouterPortForwardGuideMatcher.swift`
- `RouterPortForwardGuideComposer.swift`
- `RouterPortForwardGuideRuntimeResolver.swift`
- `RouterPortForwardFallbackDecisionTree.swift`
- `RouterPortForwardTroubleshootingEngine.swift`
- `RouterPortForwardGuideMaintenance.swift`

Do not introduce router-help content as one-off SwiftUI view code.

## Source-of-truth rule

For the current implementation, guide content lives in `RouterPortForwardGuideSeedData` inside `RouterPortForwardGuidesFoundation.swift`.

If the project later moves guide content to JSON or remote guide packs, keep the same structured schema and keep validation strict.

## Adding a new guide

1. Decide whether the new guide is actually a new family guide or just a variant covered by an existing family.
2. Prefer family-level guidance over model-by-model duplication.
3. Add the new guide to `RouterPortForwardGuideSeedData.v1Guides`.
4. Reuse the shared composition system instead of embedding repeated intro/prerequisite/troubleshooting content in the guide itself.
5. Run the hard validator and the maintenance linter before shipping.

## Required authoring fields

Every guide must have:

- stable `id`
- `displayName`
- `category`
- `family`
- `searchKeywords`
- `adminSurface`
- `steps`
- `troubleshooting`
- `review.sourceConfidence`

Use `providerDisplayName` for ISP gateway guides when relevant.
Use `deviceDisplayName` whenever possible so provider and device can stay distinct.

## Search keyword rules

Keywords should include the main ways a real user might search:

- provider name
- router brand
- product line or family name
- common model nicknames
- app name when the router is usually found by app

Avoid duplicates after normalization.
Avoid giant lists of weak keywords that could misroute other families.

## Confidence and review rules

Every guide should set an honest confidence level:

- `verifiedRecently`
- `commonFlow`
- `olderInterfaceMayVary`
- `communityBased`

Whenever a guide is materially verified or revised, update `lastReviewed` with a full ISO-8601 timestamp.

If the guide has not been checked for a long time, either:

- verify it again, or
- lower the confidence level

Do not leave a guide marked `verifiedRecently` if that is no longer true.

## Shared-section discipline

The structured guide system already has shared sections for:

- intro
- prerequisites
- value summary
- troubleshooting footer

Default to keeping these enabled.
Disable a shared section only when leaving it on would make the guide incorrect or misleading.

## Step-writing rules

Guide steps should be:

- short
- direct
- action-oriented
- realistic about variation across firmware versions

Prefer:

- “Log in to the router app or admin page.”
- “Find Port Forwarding, NAT Forwarding, or Virtual Server.”
- “Target the host Mac’s local IP.”

Avoid long prose paragraphs and avoid repeating shared content inside every step list.

## Notes rules

Use notes for:

- menu aliases
- hidden advanced settings
- app-vs-browser quirks
- firmware variation
- transparency about limits

Do not use notes to restate the entire guide.

## Troubleshooting linkage rules

Every guide should point into the shared troubleshooting system.
At minimum, most router guides should cover some mix of:

- local IP changed
- wrong router
- wrong device
- wrong protocol
- double NAT
- CGNAT
- firewall blocked
- router reboot required

If a guide needs a new troubleshooting case, add the topic to the shared topic list first rather than inventing one-off guide-specific prose.

## Provider vs device rule

Do not conflate ISP with router device.

Examples:

- “Spectrum” may be a Spectrum gateway or just the ISP
- the actual router may be ASUS, eero, TP-Link, or something else
- a mesh system may sit behind ISP hardware

Keep provider identity and device identity separate in guide metadata and copy.

## Maintenance checklist for edits

Before shipping a guide addition or revision:

1. Verify the guide still belongs to the right family.
2. Check that `searchKeywords` include the main real-world aliases.
3. Check that `providerDisplayName` and `deviceDisplayName` are still accurate.
4. Confirm all step ids are unique.
5. Confirm troubleshooting references still resolve.
6. Confirm `lastReviewed` is updated if the flow changed.
7. Confirm confidence level is still honest.
8. Confirm shared sections were not disabled without a reason.
9. Run the maintenance linter and fix errors before shipping.

## In-code helper added in Phase 8

`RouterPortForwardGuideMaintenance.swift` adds:

- a maintainer-facing linter layered on top of the hard validator
- warnings for stale review dates, missing provider/device metadata, missing admin hints, shared-section drift, and similar hygiene issues
- a simple guide stub helper for adding new family guides consistently

Use that helper as a starting point, then replace placeholder content with real guide data.
