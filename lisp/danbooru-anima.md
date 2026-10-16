# Writing Anima prompts with danbooru.el

Researched 2026-10-16 against the [official CircleStone Labs model card](https://huggingface.co/circlestone-labs/Anima#prompting).

Anima accepts tags, English captions, or a mixture. Its authors recommend
lowercase tags with spaces, retaining underscores in `score_N`. Artist names
need an `@` prefix. For several characters, name and describe each person's
appearance instead of supplying only names. For pure prose, aim for at least
two descriptive sentences.

For the tag portion, the recommended sections are quality/meta/year/safety,
subject count, character, series, artist, then general attributes. Tags within
each section may appear in any order, and prose may be mixed with tags.

Aesthetic does not need quality tags; its authors advise avoiding score tags
in both prompts. Turbo is designed for CFG 1 and 8–12 steps. The general
Base recommendation of 30–50 steps and CFG 4–5 should not be applied to Turbo.
See the [version and settings notes](https://huggingface.co/circlestone-labs/Anima#versions).

## What the compiler now does

- Reads Lisp or JSON without evaluating prompt forms.
- Lowercases symbol tags and converts underscores to spaces by default:
  `LONG_HAIR` becomes `long hair`, and `SCORE_7` becomes `score_7`.
  Set `danbooru-lowercase-tags` to nil to preserve symbol case.
- Leaves quoted strings intact, including capitalization, underscores and
  weights such as `"(chibi:2)"`. `$POSE` and `$pose` remain distinct markers.
- Flattens nested lists, substitutes variations, and removes duplicate tags.
  Nesting is an editing aid; it does not bind attributes to particular people.
- Expands `(:artist Some_Artist "@Other Artist")` to
  `@some artist, @other artist`. Place it where you want artist tags to appear.
  This explicit context normalizes quoted artist names too. It also works
  inside tag lists, including comic `:tags` and variation values.
- Appends each `(:caption "...")` after the tags on a separate line. Captions
  support variations, preserve prose capitalization, and gain a final period
  if needed. Caption-only prompts are supported.
- In comics, combines captions from the top level, defaults, scene and panel
  in that order. Each actor retains a separate appearance/outfit/pose block.
  Positions such as `left` become `on the left`; existing phrases such as
  `"beside the door"` are retained.

Tag order remains authored order. No quality, rating or negative tags are
inserted automatically, and generation settings remain under your control.
With the local workflow, negative prompts require CFG greater than 1, so
editing negatives at Turbo's CFG 1 will not help. A server keeps its loaded
checkpoint; `:model` only selects a model when using the script backend.

## A hybrid prompt

The following compiles to one image request. It is also saved as
[`examples/anima-hybrid.danbooru`](examples/anima-hybrid.danbooru).

```lisp
(1girl solo)
(short_hair brown_hair green_eyes glasses sweater)
(upper_body indoors cafe sunlight)
(:caption "An adult woman with short brown hair and glasses holds a ceramic cup with both hands beside a cafe window. Warm sunlight falls across her green eyes and sweater while the tables behind her remain softly shaded.")
(:size 1024 1024)
(:seed 42)
```

Compiled positive prompt:

```text
1girl, solo, short hair, brown hair, green eyes, glasses, sweater, upper body, indoors, cafe, sunlight
An adult woman with short brown hair and glasses holds a ceramic cup with both hands beside a cafe window. Warm sunlight falls across her green eyes and sweater while the tables behind her remain softly shaded.
```

JSON objects accept `"caption"` as a string or array of strings and `"artist"`
as a name or array of names. JSON tag strings retain their literal spelling;
write `"long hair"`, rather than `"long_hair"`.

Use tags for identifying visible attributes and sentences for who holds what,
where people stand, and how they interact. Prefer a few precise details over
synonyms or conflicting tags. These are authoring choices, not a measured
guarantee of better output. Preview with `C-c C-p`, then compare images while
keeping the checkpoint, seed, dimensions and sampling settings fixed.

Reload with `M-x load-file` and select `danbooru.el`. Existing prompt files
are not rewritten; the updated starter is used for a new empty prompt buffer.
Compiler tests and example compilation do not generate images.
