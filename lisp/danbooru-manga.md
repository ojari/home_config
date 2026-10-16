# Manga prompts in Emacs

Reload `danbooru.el` using `M-x load-file`, then open
`examples/manga.danbooru`. The example defines two characters, four outfits,
two scenes and three panels. The reaction panel has two alternatives, so
the file compiles to four images.

For a complete story, open
[`examples/kyoto-day/kyoto-day.danbooru`](examples/kyoto-day/kyoto-day.danbooru).
It follows two adult Japanese friends through a Kyoto farewell day: aikido,
lunch, tea, a neighbourhood bath, a prearranged geiko visit, karaoke, and
the journey home. The [storyboard](examples/kyoto-day/storyboard.md) defines
24 screens with three panels each, including dialogue and reading order.
Screen layouts and panel IDs are also recorded in
[`storyboard.json`](examples/kyoto-day/storyboard.json). This example compiles
to **72 individual images**; `C-c C-c` queues all of them. Use `C-c C-g`
inside a panel form to generate one at a time. Screens and lettering are
assembled separately from the current image-generation workflow.

| Key | Action |
| --- | --- |
| `C-c C-p` | Preview all compiled prompts and copy them to the kill ring |
| `C-c C-c` | Generate all panels and their variants |
| `C-c C-r` | Generate all again with fresh random seeds |
| `C-c C-v` | Preview the panel containing point |
| `C-c C-g` | Generate the panel containing point |
| `C-c C-n` | Reroll the panel containing point |
| `C-c C-k` | Cancel the request and pending jobs |
| `M-TAB` | Complete tags, or scene/outfit/character references |
| `C-c C-j` | Jump by name with Imenu, grouped by Characters, Outfits, Scenes and Panels |
| `M-n` / `M-p` | Move to the next / previous named definition in file order |

The same index works with `M-x consult-imenu` or an Imenu sidebar.
Navigation works while a definition is still being edited. Reloading
`danbooru.el` also updates navigation in existing Danbooru buffers.

Preview does not contact the image backend. Generation uses the existing
`danbooru-server` setting or, when it is nil, `danbooru-script`.
The server has one loaded model; `:model` selects a model only in script mode.

For Anima-specific syntax and a hybrid tags/caption example, see
[Writing Anima prompts](danbooru-anima.md).

## Definitions

All forms are declarative data, read without evaluating Lisp expressions.
Names are non-keyword symbols. Definitions may appear in any order; panels
are generated in their order in the file. Names must be unique within each
definition type.

| Form | Properties |
| --- | --- |
| `(:defaults ...)` | `:tags`, `:caption` (string), `:neg`, generation options |
| `(:character NAME ...)` | `:description` (string), `:tags` |
| `(:outfit NAME ...)` | `:tags` |
| `(:scene NAME ...)` | `:tags`, `:caption` (string), `:neg`, `:cast` |
| `(:panel NAME ...)` | `:scene`, `:actors`, `:camera`, `:tags`, `:caption` (string), `:action` (string), `:neg`, `:vary`, generation options |

Generation options are `:model`, `:size`, `:steps`, `:cfg` and `:seed`.
Their precedence is Emacs settings, then legacy top-level directives,
then `:defaults`, then panel properties. `:steps nil` and `:cfg nil` leave
the choice to the backend. Sizes need two positive integers, steps a
positive integer, CFG a nonnegative number, and seeds an integer of -1 or
greater. -1 requests a random seed; 0 is a valid fixed seed.

Top-level tag lists remain shared tags. Shared, default, scene and panel
tags are combined; negative prompts are combined in the same order.
Top-level `(:caption "...")` and default, scene and panel `:caption`
properties are combined as sentences after actor descriptions, before
`:action`. Captions support the same variation substitutions as tags.
For an explicit artist cue, use `(:artist some_artist)` at top level or
within a `:tags` list; it emits Anima's `@some artist` syntax.

## Scene clothes and panel actors

```lisp
(:scene cafe
 :tags (cafe indoors)
 :cast ((aya :outfit casual)
        (ren :outfit formal)))

(:panel closeup
 :scene cafe
 :actors ((aya :outfit raincoat :expression (surprised))))
```

The scene's `:cast` establishes each person's default outfit. The panel's
`:actors` selects who appears and adds position, pose, expression and tags.
An actor accepts `:outfit`, `:position` (symbol or string), `:pose`,
`:expression` and `:tags`. A panel outfit overrides the scene outfit;
`:outfit nil` removes that default. Character appearance is always included.

Omitting `:actors` includes the scene's entire cast. `:actors ()` requests
an empty scene. A panel may also add an actor not in the scene's default
cast, with an explicit outfit if needed.

Each actor becomes a separate descriptive sentence. Repeated tags are
deduplicated within that actor's sentence, while different actors retain
their own clothing and appearance. `:action` describes interactions using
visible characteristics or positions, such as "the woman on the left".
Definition names are references in the authoring language; they do not
establish identities the image model already knows.

## Variations and seeds

```lisp
(:panel reaction
 :scene cafe
 :actors ((ren :expression $FACE))
 :vary (($FACE smiling surprised))
 :seed 1234)
```

Each panel generates once unless it has `:vary`. Multiple markers within
one panel generate every combination for that panel. Markers may also
occur inside strings, clothing or character tags. Nested substitutions
are supported; cycles and unresolved markers are errors. Comic files use
panel-local `:vary`; legacy tag files retain top-level `(:vary $X ...)`.

Fixed seeds come from the effective panel options. With random seeds,
each panel gets its own seed and its variants share that seed. Reroll
commands override fixed seeds. `M-x danbooru-regenerate` from a generated
image rerolls only its panel and variants, while the image buffer remains
open with its source metadata.

Each generated PNG gets an adjacent `.png.json` file containing the original
source, panel name, resolved prompt, actual seed, requested parameters and
backend address or script path. Backend model defaults are not resolved by
Emacs; these records describe the submitted inputs. Matching seeds alone
do not guarantee character continuity.

## Validation and scope

The full file is validated before any job is queued, even when generating
just one panel. Unknown directives or properties, duplicate definitions,
missing references, malformed parameters and incomplete forms report errors.
Tag spelling is not checked against the Danbooru vocabulary. Reference
completion works while the buffer is incomplete; tag completion still uses
`danbooru-tag-file`.

This generates individual panels. Page layout, editable dialogue and image
reference conditioning can be added later. Character grouping improves the
prompt but the current backend still receives one text string.

Run the compiler and generation-queue tests with:

```sh
emacs --batch -Q --load tests/danbooru-test.el -f ert-run-tests-batch-and-exit
```
