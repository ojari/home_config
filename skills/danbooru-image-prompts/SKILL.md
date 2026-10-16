---
name: danbooru-image-prompts
description: Write and refine anime image prompts using Danbooru-style tags and Anima, including .danbooru files for Emacs danbooru.el, prompt variations, and consistent comic characters.
---

# Danbooru image prompts

Turn a visual idea into a coherent image prompt. Default to the user's Anima and `danbooru.el` workflow when that context applies. For another generator, preserve the visual brief and adapt to its documented prompt syntax.

## Choose the deliverable

- For a single image in Emacs, write grouped Lisp data in a `.danbooru` file.
- For direct input into a generator, return comma-separated tags, with a short natural-language sentence when relationships need clarification.
- For controlled alternatives, use `:vary`; say how many jobs the combinations produce.
- For recurring characters or a comic, use named characters, outfits, scenes, and panels. Read [the format reference](references/danbooru-format.md) for syntax and inheritance.
- A prompt-writing request calls for prompt text or files. Run generation when requested as part of the task; writing or validating a prompt does not require contacting a backend.

## Build the visual brief

Extract the subject count, identifying appearance, clothing, action, expression, framing, environment, lighting, and medium. Preserve explicit choices. Make modest assumptions for missing details; ask only when an ambiguity changes the intended image substantially.

Translate visible attributes into a small set of familiar tags. Consult [the tag starter](references/tags.md) for vocabulary and common mistakes. Use natural language for spatial relationships, object interactions, unusual materials, or a precise detail that lacks a reliable tag. Do not label invented phrases as verified Danbooru tags.

Organize for readability: model controls if needed; subject count and identity; appearance and clothing; action and expression; framing; environment and lighting; medium. This is an editing convention, not a universal claim that earlier tags always receive higher weight. Model-specific guidance takes precedence.

Prefer a few discriminating attributes to a long list of synonyms. Resolve contradictions such as `solo` with two subjects, `portrait` with visible boots, or `monochrome` with a required color palette. Separate each person's attributes when several people appear. Describe who acts on which object and where each subject stands.

## Adapt to Anima

The following model-specific rules come from the [Anima model card](https://huggingface.co/circlestone-labs/Anima), checked 2026-10-15:

- Tags use lowercase words with spaces; `score_N` retains its underscore. Quoted natural language can accompany tags.
- Suggested tag-section order: quality/meta/year/safety, count, character, series, artist, general attributes.
- Aesthetic needs no quality tags; avoid `score_*` in both positive and negative prompts. `masterpiece, best quality` may remain in an existing prompt.
- Turbo is distilled for CFG 1 and 8–12 steps. Keep backend defaults unless settings are part of the request.
- An explicitly requested artist tag uses `@` before the artist name.

In this local workflow, `:neg` is effective only when the backend uses CFG greater than 1. Changing a Turbo negative prompt at CFG 1 will not fix an image. Prefer clearer positive descriptions, fewer competing concepts, and appropriate model settings. Where negatives are active, target unwanted content or observed defects instead of appending a huge generic list.

Treat quality tags as learned model controls, not canonical content tags or guarantees. Treat `safe` as a model cue rather than a guarantee about the result. Preserve requested content instead of silently adding unrelated aesthetic or rating tags.

## Write `.danbooru` data correctly

The local implementation is `~/home_config/lisp/danbooru.el`. Its source overrides this reference if the format changes.

- Forms are read as data, without an apostrophe or executable Lisp wrappers. Nested lists group tags for the writer; they do not bind attributes to subjects or strengthen attention.
- Symbol underscores become spaces by default, except names beginning `score_` or `$`. Strings retain their internal spelling and punctuation; surrounding whitespace is trimmed.
- Exact duplicate flattened strings are removed, retaining the first occurrence. Repetition is not a weighting mechanism.
- Quote tags containing parentheses or reader punctuation. A backend weight such as `"(chibi:2)"` must be a string; `(chibi:2)` is merely a list in this format. Use weights only if the actual backend supports them.
- Use `(:vary $POSE standing sitting)` for a simple batch, and `:vary (($POSE standing sitting))` inside a panel. Multiple variation axes form a Cartesian product.
- The server uses its loaded model and ignores `:model`. Do not promise a model switch from editing this directive alone.

Single-image example:

```lisp
;;; Cafe portrait -*- mode: danbooru-prompt -*-
;; subject and appearance
(1girl solo (short_hair brown_hair green_eyes) glasses)
;; clothing, action, expression
(sweater holding_cup smile)
;; composition and environment
(upper_body indoors cafe sunlight)
("An adult woman holds a ceramic cup with both hands beside a window.")
(:size 1024 1024)
(:seed 42)
```

Compiled positive prompt:

```text
1girl, solo, short hair, brown hair, green eyes, glasses, sweater, holding cup, smile, upper body, indoors, cafe, sunlight, An adult woman holds a ceramic cup with both hands beside a window.
```

## Check and refine

For `.danbooru` files, compile with the local `danbooru--expand` function or use `C-c C-p` in `danbooru-prompt-mode`. Compilation checks syntax and references without generating images. See [the format reference](references/danbooru-format.md) for a batch command.

Check the compiled prompt for lost punctuation, unresolved placeholders, conflicting counts, and attributes assigned to the wrong person. Inspect job counts before presenting variations. When images are available, keep the model, seed, size, sampler, and settings fixed while changing one concept at a time; reroll afterward to check whether the improvement generalizes. A fixed seed helps comparison but does not guarantee identical output across backends or recurring character identity.

Deliver the requested prompt or file, the compiled preview when useful, and only the settings or assumptions that affect its use. Report whether validation covered compilation or actual generated images. Read [research notes and sources](references/research.md) when explaining the evidence or updating this skill.
