# Local `.danbooru` format

Verified against `~/home_config/lisp/danbooru.el` and its compiler tests on 2026-10-15. This format is specific to the Emacs package; it is not Danbooru website syntax.

## Simple prompts and variations

```lisp
;;; Forest study -*- mode: danbooru-prompt -*-
(1boy solo (short_hair black_hair brown_eyes))
(jacket pants boots $POSE)
(full_body outdoors forest sunlight)
(:vary $POSE standing walking)
(:size 832 1216)
(:seed 42)
```

This compiles to two jobs. Add another axis with `(:vary $FACE smile serious)` and `$FACE` in the tag tree to produce four. A list value is one alternative containing several tags, for example `(:vary $POSE standing (sitting holding_book))`. Markers can occur inside strings. Use exact, distinct marker names and avoid unresolved markers even though legacy mode does not reject every such mistake.

Simple batches share one actual seed. `(:seed -1)` requests a random seed; a nonnegative integer fixes it. Panel variants share that panel's actual seed. Rerolling overrides file seeds.

Available top-level generation directives:

| Directive | Meaning |
| --- | --- |
| `(:model turbo)` or `(:model aesthetic)` | Script model choice; ignored by an already loaded server |
| `(:size 832 1216)` | Positive integer width and height |
| `(:steps 12)` | Positive integer sampling steps; `nil` inherits backend defaults |
| `(:cfg 1)` | Nonnegative guidance value; `nil` inherits defaults |
| `(:seed 42)` | Integer at least -1 |
| `(:neg blurry jpeg_artifacts)` | Negative tags; backend must apply negative conditioning |

Omit options to keep current settings. No prompt directive selects the sampler. The inspected server implementation sends `euler`; do not copy a different sampler recommendation into a nonexistent directive.

Strings are useful for special syntax: `"watercolor (medium)"` or `"An adult woman on the left hands a book to the man on the right."`. The Lisp reader treats bare parentheses as list structure and semicolons as comments. A raw flat prompt is best returned as text for a generator; quote the entire string if putting it into a `.danbooru` file to avoid reader punctuation surprises.

## Recurring characters and panels

```lisp
;;; Bookshop sequence -*- mode: danbooru-prompt -*-
(:defaults :tags (lineart monochrome) :size (1024 1024) :seed 42)

(:character aya
 :description "An adult woman"
 :tags (short_hair black_hair hairclip))
(:character ren
 :description "An adult man"
 :tags (short_hair brown_hair glasses))
(:outfit casual :tags (sweater pants))
(:scene shop
 :tags (indoors bookshelf)
 :cast ((aya :outfit casual) (ren :outfit casual)))

(:panel exchange
 :scene shop
 :camera (upper_body)
 :actors ((aya :position left :pose (holding_book) :expression (smile))
          (ren :position right :expression (surprised)))
 :action "The woman on the left offers a book to the man on the right.")

(:panel reaction
 :scene shop
 :camera (portrait)
 :actors ((ren :expression $FACE))
 :vary (($FACE smile serious))
 :seed 99)
```

This produces three jobs: `exchange`, then two `reaction` alternatives. Each job is a separate image, rather than an assembled comic page.

The compiler emits global tags, a person-count sentence, one description per actor with that actor's appearance/outfit/pose/expression, then action text. Character definitions hold stable appearance; outfits hold clothing; scenes hold locations and default outfits. Actor lists keep attribute ownership readable, but the flattened text cannot guarantee the model will bind every attribute correctly.

Supported properties:

| Definition | Properties |
| --- | --- |
| `:defaults` | `:tags :neg :model :size :steps :cfg :seed` |
| `:character NAME` | `:description :tags` |
| `:outfit NAME` | `:tags` |
| `:scene NAME` | `:tags :neg :cast` |
| `:panel NAME` | `:scene :actors :camera :tags :action :neg :vary` and generation options |
| Scene cast member `(NAME ...)` | `:outfit` |
| Panel actor `(NAME ...)` | `:outfit :position :pose :expression :tags` |

Use symbolic names and define referenced characters, outfits, and scenes. `:description` and `:action` are strings. `:position` is a string or non-keyword symbol, such as `left`. Put variations inside panels once any story definitions are present; story mode requires at least one panel.

Generation options resolve in this order: top-level, defaults, panel; later values win. Positive tags accumulate from top-level, defaults, scene, camera, and panel, followed by actor descriptions and action. Negatives accumulate from top-level, defaults, scene, and panel. Adding a contradictory later tag does not remove an earlier one; move variable properties to the appropriate layer.

An omitted `:actors` uses the scene cast. An explicit actor list selects only those characters, inheriting each matching scene outfit unless overridden. `:actors ()` emits no people. Set count tags accordingly; do not place `solo` in shared defaults for a multi-person scene.

JSON supports the legacy format only: arrays or an object with `tags`, `vary`, `neg`, `model`, `size`, `steps`, `cfg`, and `seed`. JSON strings retain underscores because they are strings. Author named comic definitions as Lisp forms.

## Preview without generation

In Emacs, `C-c C-p` previews all jobs and copies their positive prompts. Inside a panel, `C-c C-v` previews that panel. `M-x danbooru-edit-prompt` opens the configured default file.

For an existing file, replace the final path below and run:

```bash
emacs --batch -Q -l "$HOME/home_config/lisp/danbooru.el" \
  --eval '(let ((jobs (with-temp-buffer
                       (insert-file-contents (car command-line-args-left))
                       (danbooru--expand (buffer-string)))))
            (princ (format "%d jobs\n" (length jobs)))
            (dolist (job jobs) (prin1 job) (terpri)))' \
  /absolute/path/prompt.danbooru
```

This loads the source `.el` explicitly, avoiding an older `.elc`, and compiles only. Generation keys are `C-c C-c` for all jobs and `C-c C-g` for the current panel. Named panels overwrite their previous `PANEL.png`, including successive variants, so preserve an output before generating another variant if comparison matters. JSON sidecars record the resolved prompt, actual seed, and parameters. The configured generator script was absent at research time; compilation remains available without it.
