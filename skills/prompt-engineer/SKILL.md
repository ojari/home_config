---
name: prompt-engineer
description: Write, review, and refine prompts whose main job is to make an LLM or coding agent (Claude Code, Codex, API code generators) write or change code. Use for task prompts, system prompts for code-generating tools, CLAUDE.md/AGENTS.md instructions, subagent briefs, and SKILL.md files.
---

# Prompt engineer for code-writing prompts

Write the prompt a capable new colleague would need to do the job without a
follow-up question. Current models already read code well, follow plain wording,
and keep working through an agreed task. Most failures come from missing
information or no way to check the result, not from weak wording. Spend the
prompt's words on those gaps.

## Choose the deliverable

| Request | Deliverable | Where it lives |
| --- | --- | --- |
| One coding task | Task prompt | Pasted into a session, `claude -p`, or `codex exec` |
| Recurring repo knowledge | A few lines | `CLAUDE.md` / `AGENTS.md`, or a path-scoped rule file |
| Reusable procedure | Skill | `skills/<name>/SKILL.md` (see "Skills" below) |
| Work for another agent | Subagent brief | Agent/Task tool prompt |
| An app that generates code through an API | System prompt plus a user-turn template | Application code |
| An existing prompt that misbehaves | Diagnosis and a revised prompt | Same place as the original |

Durable rules belong in instruction files or skills, not repeated in every task
prompt. A rule that must hold without exception belongs in a hook, deny rule,
test, or CI check. Prompt wording only makes it likely.

## Gather what the agent cannot see

Read the target repo, its instruction files, and the code the task touches
before writing. Do not restate what the agent will find by reading the repo
itself: layout, language, framework, existing patterns. Ask the user only for
facts that change the prompt materially. Otherwise state the assumption in the
prompt.

The agent cannot discover:

- the goal behind the task and the observed symptom (error text, steps, logs)
- decisions made outside the repo, and a preference between two reasonable designs
- scope: the minimal fix or the full feature with edge cases, error states, and follow-ons
- which files or directories are off limits, and which outside resources it may use
- the commands that prove the work is done, if those are not obvious from the repo

## Build a task prompt

Cover four parts, in plain prose or short sections. Omit a part only when it is
truly obvious.

1. **Goal:** the behavior to add or fix, stated as an outcome. Use imperative
   verbs (`Change`, `Add`, `Fix`) when edits are wanted. "Can you suggest..." gets
   suggestions, not edits.
2. **Context:** the specific files, symbols, and an example to imitate ("follow
   the pattern in `HotDogWidget.php`"). Paste the actual error, log, spec, or
   screenshot rather than describing it.
3. **Constraints:** what must not change (public APIs, file formats, dependencies,
   "no new libraries"), the target platform and versions, and the style to match.
   Explain the reason behind a non-obvious constraint so the model can generalize
   it.
4. **Done when:** a check the agent can run that passes or fails, such as a test,
   build, lint, typecheck, or diff against a fixture. Ask for evidence in the final
   report: the command run and its result.

Example:

```text
Users report that login fails after the session times out. Look at token refresh
in src/auth/. Write a failing test that reproduces it, then fix the cause. Don't
change the public AuthClient API, which is used by the mobile app. Done when
`pnpm vitest run src/auth` passes. Report the command output.
```

For a fuzzy or large feature, don't guess the spec. Ask the agent to interview
the user and write `SPEC.md`, then implement it in a fresh session against that
spec. For multi-step work, ask for a plan first and keep progress in a file or in
git so a later session can resume.

## Calibrate behavior

Add a calibration line only for behavior you expect or have observed to go wrong:

- **Scope:** Models tend to build the smallest thing that satisfies the request.
  When the full version is wanted, say so and list it ("be ambitious: empty and
  error states, keyboard navigation"). When a minimal change is wanted, say:
  "Only change what this requires; no unrelated refactors, extra configurability,
  or speculative error handling."
- **Grounding:** "Read the relevant code before answering or editing; don't make
  claims about code you have not opened."
- **Gaming tests:** "Implement the general logic, not something that only fits the
  test inputs. If a test looks wrong, report it instead of working around it."
- **Action vs. advice:** State whether the agent should edit files or only
  propose changes.
- **Risky actions:** Say which irreversible or shared actions require
  confirmation, such as push, delete, migrations, or posting externally.
- **Agent briefs:** A subagent knows only its brief. State the goal, what is
  already ruled out, the files to read, the scope, and the expected report shape.
  Give a reviewer the code and the spec, not your conclusion.

Avoid the outdated workarounds. ALL CAPS, `IMPORTANT`, and `CRITICAL: you MUST`
make current models over-apply a rule. `think step by step`, `be thorough`, and
"keep going, don't be lazy" are ordinary text. Use effort/reasoning settings for
depth and a runnable check for completion. Remove contradictory instructions. When
two rules can conflict, state which one wins.

## System prompts for code-generating applications

- Give the role and audience in one or two sentences, then the rules, each with
  its reason.
- Separate instructions, context, examples, and variable input with consistent
  tags such as `<instructions>`, `<context>`, `<example>`, and `<input>`. Put long
  reference material before the question.
- Specify the output contract exactly: language and version, a single code block
  or full files or a unified diff, whether prose is allowed, and file naming. For
  machine-parsed output, prefer structured outputs or tool schemas over format
  instructions alone.
- Use 3–5 relevant, varied examples when format or style matters. Each example
  should match the real task closely. Vary them so the model does not copy an
  incidental detail.
- Validate generated code mechanically (parse, compile, run tests) instead of
  asking the model to promise correctness.

## Instruction files and skills

- `CLAUDE.md` and `AGENTS.md` load on every task, so keep them short. Include exact
  commands for test, build, lint, and running one test; misleading code to avoid
  copying; decisions not recorded in code; and corrections needed twice. Leave out
  architecture tours that the agent can read from the repo.
- Skills: write YAML frontmatter with a lowercase hyphenated `name` and a
  `description` that says what the skill does and when to use it. The description
  is the only part visible before the skill loads, so it must carry the trigger.
  Keep `SKILL.md` compact. Move provenance, long references, and examples into
  `references/` and link them from where they are needed. In this repo, skills
  live in `~/home_config/skills/<name>/` and `update.sh` symlinks them into both
  Claude Code and Codex. Use only metadata both tools understand.

## Review and test a prompt

Apply the colleague test: could someone without the conversation do the task from
this prompt alone? Then check:

- the goal is an observable outcome, and the done-when check is runnable
- every constraint can be checked; no two rules contradict each other
- nothing restates what the repo already says, and no rule relies on emphasis
- examples are labeled as examples and do not leak irrelevant specifics

When a prompt underperforms, change one thing at a time against the same task and
compare the resulting diffs and check results, not the wording. Rerun a few times
before concluding, because a single run is noisy. Report whether the prompt was
actually run or only reviewed.

Deliver the prompt ready to paste, followed by a short note of the assumptions and
anything the user still has to fill in. Read [the research notes](references/research.md)
when the sources or rationale are needed, or when updating this skill.
