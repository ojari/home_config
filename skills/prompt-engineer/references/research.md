# Prompt engineer skill: research notes

Researched 2026-10-28. Scope: prompts whose main output is code, written for
agentic coding tools (Claude Code, Codex) or for applications that generate code
through a model API. The skill is a synthesis of the vendor sources below. Vendor
guidance is measured on that vendor's models; re-check a model-specific claim
before applying it to another model.

## Main findings

**Missing information and missing checks cause most failures.** The Claude Code
guide attributes most failed sessions to three causes: information the agent
can't see in the repo, no check that tells it whether the work is done, and
rules that a prompt can't guarantee. Its test for writing something down is
whether the agent could find it by reading the code and would actually look.
If both answers are yes, leave it out.
[Claude Code best practices](https://code.claude.com/docs/en/best-practices).

**A task prompt has four parts.** OpenAI's Codex guide names goal, context,
constraints, and a done-when condition. The Claude Code guide gives the same
shape by example ("look at token refresh in src/auth/, write a failing test that
reproduces it, then fix it"; "follow the pattern in HotDogWidget.php ... no new
libraries"). Both recommend handing over the real file, error, or screenshot
instead of describing it.
[Codex best practices](https://learn.chatgpt.com/guides/best-practices).

**Give a runnable pass/fail check and ask for evidence.** Claude Code: "Give
Claude something it can run that comes back pass or fail". Ask for the command
and its output rather than "all tests pass". Codex likewise lists writing or
updating tests, running suites, lint/types, and reviewing the diff. A reviewer
asked to find problems will always find something, so scope review prompts to
correctness and add "skip style".

**Plain wording beats emphasis. Explain the reason.** Anthropic's prompting
guide: be clear and direct; explain *why* ("read aloud by a text-to-speech
engine, so never use ellipses") so the model generalizes. Current models can
over-trigger on "CRITICAL: You MUST"; use "Use this tool when ...". The Claude
Code guide lists ALL-CAPS emphasis, "think harder", and "keep going, don't be
lazy" as obsolete. Effort settings control depth, and a check controls
completion. OpenAI found the same with GPT-5 in Cursor. Softening "be THOROUGH"
reduced excessive searching, and contradictory instructions made the model waste
reasoning reconciling them.
[Claude prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices),
[GPT-5 prompting guide](https://developers.openai.com/cookbook/examples/gpt-5/gpt-5_prompting_guide).

**Scope has to be stated.** Claude reads requests conservatively; "be ambitious"
plus a list of the expected extras signals full scope. In the opposite direction,
Anthropic's sample anti-over-engineering prompt covers scope, documentation,
defensive coding, and abstractions. "Can you suggest changes" yields suggestions,
and "Change this function" yields edits.

**Targeted calibration snippets.** The Anthropic guide offers tested blocks for:
investigating code before answering (`<investigate_before_answering>`), avoiding
hard-coding to tests and reporting bad tests, cleaning temporary files,
confirming irreversible actions, and limiting subagent use. The skill paraphrases
these. Add them only for observed or expected failures.

**Structure and examples.** Use XML-style tags to separate instructions, context,
examples, and inputs. Use 3–5 relevant, diverse examples wrapped in `<example>`
tags. OpenAI's GPT-5 guide also reports better adherence from XML-style sections
and recommends encoding codebase conventions explicitly so generated code blends
in.

**Instruction files stay short; procedures go to skills.** Claude Code:
`CLAUDE.md` loads every session, so keep exact commands, misleading code,
decisions outside the repo, and anything corrected twice. Codex: AGENTS.md
should be short and accurate. Add rules after repeated mistakes and reference
task-specific files for long guidance. Both guides treat a durable rule
repeated in prompts as a mistake. Rules that must never be broken belong in
hooks or deny rules.

**Plan or interview for fuzzy work.** Both vendors recommend having the agent
interview the user or plan before coding for ambiguous or multi-step tasks.
Claude Code suggests writing `SPEC.md` and then building in a fresh session.
Anthropic recommends progress files and git for state across context windows.

## Sources consulted

| Source | Used for |
| --- | --- |
| [Claude Code best practices](https://code.claude.com/docs/en/best-practices) | What to write down, specific prompts, checks, hooks vs. instructions, obsolete advice |
| [Claude prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices) | Clarity, context/why, examples, XML tags, tool action, over-engineering, hallucination, test-gaming snippets |
| [OpenAI GPT-5 prompting guide](https://developers.openai.com/cookbook/examples/gpt-5/gpt-5_prompting_guide) | Agentic eagerness, contradictions, Cursor code-quality lessons, XML sections |
| [Codex best practices](https://learn.chatgpt.com/guides/best-practices) | Goal/context/constraints/done-when, AGENTS.md scope, verification, common mistakes |
| [Skill authoring notes in software-architect](../../software-architect/references/research.md) | Shared Codex/Claude skill format and discovery locations |

Secondary blog posts from the same search were consistent with these sources
("clearer specs, not longer prompts"; define done; review diffs). They added no
claims the skill relies on.

## Lightweight evaluation

Use these scenarios to evaluate the skill. They are not completed tests:

- **Vague bug report** ("login is broken"): The skill should ask for or insert
  the symptom, locate the code, require a reproducing test, and give a runnable
  done-when.
- **Bloated CLAUDE.md:** It should cut architecture tours and ALL-CAPS rules,
  keep commands and non-obvious decisions, and move no-exception rules to hooks.
- **Codegen API system prompt:** It should define the output contract, separate
  input with tags, give varied examples, and validate generated code mechanically.
- **Subagent brief for a review:** It should provide the code and the spec instead
  of the author's conclusion, limit findings to correctness, and define the report
  shape.
