# Manga prompts with definitions and variations

Use the same tag mini language for single images and sequences of images.
Define reusable appearance, clothing, environments, and complete shots with
`:def`, then choose shots with `:vary`.

The complete [manga example](examples/manga.danbooru) produces four images:
a meeting, two reaction alternatives, and a departure. For imported
libraries, see [Reusable prompt libraries](danbooru-library.md).

## Compose reusable data

```lisp
(:def person/aya (long_hair black_hair hairclip))
(:def outfit/casual (sweater long_skirt))
(:def scene/cafe (cafe indoors daytime))
(:def shot/greeting
 (1girl solo person/aya outfit/casual scene/cafe waving))
(:def shot/reading
 (1girl solo person/aya outfit/casual scene/cafe sitting holding_book))

(manga monochrome lineart $SHOT)
(:vary $SHOT shot/greeting shot/reading)
(:size 1024 1024)
(:seed 31415)
```

This produces two jobs in the order written. Definition names have no
special types: `person/`, `outfit/`, `scene/`, and `shot/` are optional
prefixes. Any definition can combine other definitions, and definitions
may appear before or after their references. Unused definitions emit no
tags. All names are case-sensitive.

Nested lists flatten into one comma-separated prompt and duplicate tags
are removed. Lists do not associate attributes with particular people.
For multiple people, include natural-language strings describing each
person's appearance, clothes, position, and action. A shared `:caption`
can add sentences after the tags; variation markers inside captions are
substituted too.

## Preview or generate selected shots

- `C-c C-p` previews the compiled prompts and copies them to the kill ring.
- `C-c C-c` generates all variation combinations.
- `C-c C-r` generates them with a fresh seed.
- Select complete alternatives inside one `:vary` to preview or generate
  only that subset with the same commands.
- `C-c C-k` cancels running and queued work.
- `C-c C-j` opens Imenu for local `:def` names; `M-n` / `M-p` move between them.

An alternative can be a symbol or a nested list, for example
`(shot/reaction surprised)`. Multiple `:vary` directives produce every
combination. Put dependent choices together in a single alternative to
avoid unwanted combinations.

## Settings, files, and regeneration

Top-level settings apply to every job in a prompt. A fixed `:seed` is
reused across variants; a random seed is chosen once per generation call.
Use separate working prompt files with a shared `:include` library when
shots need different dimensions, seeds, or sampling settings.

Each image gets a timestamped filename, with an index and label for
batches. File-backed prompts save in a subdirectory named after the
prompt file. Rerolls produce new files. A neighboring JSON file records
the self-contained source, resolved prompt, actual seed, requested
parameters, and backend.

`M-x danbooru-regenerate` uses the source remembered in the image buffer,
or the last prompt, and requests a fresh seed. For a selected variation
subset it preserves that subset. Imported definitions are saved as an
expanded source snapshot, so regeneration does not depend on later
library edits.

This workflow generates individual images. Page layout, lettering, and
image reference conditioning belong to separate tools.
