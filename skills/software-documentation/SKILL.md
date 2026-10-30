---
name: software-documentation
description: Write and revise software design documents and technical design RFCs for experienced software designers, using Mermaid/SVG diagrams and links to existing Obsidian knowledge. Use for documenting a proposed or existing software design; architecture exploration alone and standalone concept notes belong to their respective skills.
---

# Software Documentation

Write clear, compact documents for experienced software designers. Explain what
readers need to assess the design and work with it later. Follow the requested
destination and local document conventions.

## Design document foundation

Adapted from [Design Docs at Google](https://www.industrialempathy.com/posts/design-docs-at-google/).
Use a flexible structure, sized to the problem:

- **Context and scope:** Give objective background and define the system boundary.
- **Goals and non-goals:** State desired outcomes and plausible capabilities
  deliberately excluded from this effort.
- **Design:** Start with an overview, then explain consequential decisions and
  their tradeoffs. Sketch interfaces and storage only at the detail needed to
  understand those choices; link full definitions and prototypes.
- **Alternatives:** Compare credible options against the goals and explain the
  choice. Avoid strawman alternatives.
- **Cross-cutting concerns:** Address relevant security, privacy, and observability
  impacts; link dedicated treatments.

Keep small changes small. Do not fill a long template when a short decision record
will serve. Use review to resolve uncertainty early. Revise the document when
implementation changes its conclusions, and link later amendments so readers can
find the current design.

The Obsidian reuse rules, writing preferences, and visual guidance below extend
this foundation for this workflow.

## Establish the evidence

Read applicable project instructions, related documents, relevant code, and tests.
Identify whether the request describes a proposal or the implemented system.
Distinguish observed behavior, proposed behavior, assumptions, and open questions.
Never present inferred intent as a recorded decision or invent measurements.

For existing software, support consequential claims with source paths and symbols;
record the revision when it matters. For proposals, identify unverified assumptions
and how they could be checked. Ask only for missing information that materially
changes the document; otherwise state the assumption and continue.

Include ownership, concurrency, state transitions, failure handling, timing, or
resource limits where they affect this design. Describe migration, rollback, and
validation when a proposed change needs them. Do not turn these into compulsory
sections for every document.

## Reuse Obsidian knowledge

Before drafting explanations, search the known vault and project documentation
for the relevant concepts, components, decisions, and aliases. Read candidate notes
to verify coverage; a matching title alone is insufficient. Discover the vault
from available project context or configuration rather than scanning the whole
home directory. If it is unavailable, disclose that reuse could not be checked.

- Link an existing explanation instead of rewriting it. Add only a short bridge
  explaining how it applies here, plus the new project-specific decision or delta.
- Link to a heading or block when that is more precise. Verify the target and
  use the vault's established link style. Do not create speculative note links.
- Keep the current document understandable: name the relevant constraint or
  conclusion, then link its explanation. Avoid copied paragraphs and embeds that
  reproduce the existing treatment.
- If a note conflicts with the code or proposal, explain the discrepancy and the
  evidence. Do not silently propagate stale claims or rewrite unrelated notes.
- For documents outside the vault, use links readers can actually follow. If the
  canonical note is inaccessible to the intended audience, identify that gap
  rather than assuming an Obsidian wikilink will work there.

For output inside Obsidian, follow local properties, attachment paths, and naming
conventions. Use the Obsidian technical notes skill when vault-specific work needs
its guidance; this skill does not depend on its installation.

## Draw to clarify

Actively look for explanations that become clearer as a drawing or chart. Include
the visual when it helps readers reason; do not add decoration or impose a quota.
Keep each figure focused on one question and place it near the relevant text.

| Question | Preferred visual |
| --- | --- |
| What connects to what, and across which boundary? | Mermaid flowchart with labeled edges and boundary groups |
| Who acts in which order? | Mermaid sequence diagram, including consequential failure paths |
| What transitions are allowed? | Mermaid state diagram with triggers and guards |
| How is space or a physical structure arranged? | SVG drawing of memory, packet fields, hardware, or layout |
| How do quantities or options compare? | Chart with units and assumptions, or a compact comparison table |

Use fenced `mermaid` blocks for supported diagrams. Prefer conservative syntax
compatible with the destination renderer. Name components consistently with the
text, distinguish data flow from dependency direction, and label ambiguous arrows.
Separate overview and detail when one diagram becomes crowded.

Use editable, self-contained SVG when geometry or precise layout matters. Include
a `viewBox`, readable labels, accessible title/description, and sufficient contrast
for the target theme. Store assets in the established attachment directory and
embed them with the destination's Markdown syntax. Avoid raster screenshots of
diagrams that can be represented as Mermaid or SVG.

For quantitative charts, use standard plotting tools and export SVG when practical.
Label units, scales, data sources, and whether values are measured, estimated, or
illustrative. Never fabricate benchmark results. A qualitative diagram is better
than a chart whose numbers imply unsupported precision.

Use a brief caption to explain the conclusion or a necessary assumption. Keep
normal Obsidian links in surrounding text when a diagram refers to another note;
links inside Mermaid alone do not establish ordinary vault backlinks.

## Keep the prose clean

Lead with the proposal or the current design's central mechanism. Use short
paragraphs, concrete nouns, and direct verbs. Assume software design experience;
explain domain-specific terms without teaching basic programming concepts.

Use headings only where they aid navigation, lists for parallel items, and tables
for comparisons. Remove filler introductions, repeated summaries, marketing
language, and narration of obvious code. Keep unfamiliar mechanisms precise
enough to reason about; brevity must not hide a constraint or failure mode.

Preserve unresolved questions and the author's intent. Mark status and actual
decisions using local conventions; do not invent approval, reviewers, or consensus.

## Check the result

Review accuracy, duplicate explanations, unsupported conclusions, links, and asset
paths. Check that figures agree with the prose and evidence. Validate Mermaid
with available tooling and SVG as XML; inspect rendered figures when possible
for clipping, overlaps, contrast, and legibility. Report rendering checks honestly.

Deliver the document and any diagram assets in the requested location, or provide
a draft if no destination is known. Report paths and material uncertainties
briefly; keep work-log chatter outside the document.
