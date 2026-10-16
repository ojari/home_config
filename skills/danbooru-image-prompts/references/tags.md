# Simple anime tag vocabulary

The table uses canonical first-column entries verified in the local completion CSV on 2026-10-15. These are useful vocabulary, not a required checklist. Counts in the CSV describe dataset usage, not how reliably a model follows a tag.

| Visual choice | Starter tags in `.danbooru` symbol spelling |
| --- | --- |
| People/count | `1girl`, `1boy`, `2girls`, `2boys`, `solo`, `no_humans` |
| Hair length/style | `short_hair`, `long_hair`, `ponytail`, `twintails` |
| Hair color | `black_hair`, `brown_hair`, `blonde_hair` |
| Eyes/accessories | `blue_eyes`, `green_eyes`, `brown_eyes`, `glasses`, `hairclip` |
| Clothes | `shirt`, `sweater`, `jacket`, `dress`, `skirt`, `pants`, `boots`, `scarf` |
| Face | `smile`, `serious`, `surprised`, `blush`, `crying`, `open_mouth`, `closed_mouth` |
| Pose/action | `standing`, `sitting`, `walking`, `running`, `waving`, `holding_book`, `holding_cup` |
| Gaze | `looking_at_viewer`, `looking_back` |
| Framing | `portrait`, `upper_body`, `full_body`, `close-up`, `wide_shot` |
| Viewpoint | `from_side`, `from_above`, `from_below` |
| Place | `indoors`, `outdoors`, `cafe`, `forest`, `street` |
| Atmosphere | `sky`, `cloud`, `sunset`, `night`, `rain`, `snow`, `cherry_blossoms` |
| Lighting/depth | `sunlight`, `backlighting`, `depth_of_field` |
| Sparse background | `simple_background`, `white_background` |
| Medium/style | `lineart`, `monochrome`, `sketch`, `chibi`, `comic`, `anime_screenshot` |

Select alternatives according to the image. `1girl` and `1boy` are counting labels, not precise age specifications; use a clear natural-language age description when relevant. `no_humans` may still allow animals or other subjects.

`portrait` emphasizes the face and shoulders; `upper_body` includes the torso; `full_body` includes the whole person; `wide_shot` places the subject farther away. These distinctions come from [Danbooru's composition wiki](https://safebooru.donmai.us/wiki_pages/tag_group:image_composition). Choose one primary framing, then add an angle if useful. Don't expect a portrait crop to display every clothing detail.

## Canonical names, aliases, and model controls

The local CSV maps `smiling` to `smile`, `clouds` to `cloud`, `watercolor` to `watercolor_(medium)`, `anime_screencap` to `anime_screenshot`, and `manga` to `comic`. The Emacs compiler does not resolve aliases: write the canonical form when that is the desired vocabulary. For watercolor use the string `"watercolor (medium)"` so parentheses remain literal.

Anima's model card prefers Gelbooru spellings when they differ from Danbooru; verified model-specific wording can therefore override the CSV. Aesthetic controls such as `best quality` and `masterpiece` are not in this local Danbooru vocabulary. Likewise, a phrase such as `soft rim light` can be useful descriptive language without being a canonical tag. Avoid presenting the CSV as a complete model vocabulary.

## Look up unfamiliar tags

The local vocabulary is configured by `danbooru-tag-file`, currently `~/work/danbooru/tags/vocab/danbooru.csv`. It contains tag, type, post count, and aliases; use CSV parsing because alias fields contain commas. Emacs provides tag completion through `danbooru-complete-tag` and completion at point.

For a quick exact-name check:

```bash
rg -n '^(smile|cloud|watercolor_\(medium\)),' "$HOME/work/danbooru/tags/vocab/danbooru.csv"
```

For definitions, consult the [tagging guide](https://safebooru.donmai.us/wiki_pages/howto:tag), [tag groups](https://safebooru.donmai.us/wiki_pages/tag_groups), [hair](https://safebooru.donmai.us/wiki_pages/tag_group:hair), or [face tags](https://safebooru.donmai.us/wiki_pages/tag_group:face_tags). The Safebooru host exposes the same Danbooru wiki and was accessible when the main host failed during research. If a tag cannot be verified, describe the intended appearance plainly rather than inventing a canonical spelling.
