# Research basis

Researched 2026-10-15. This file records provenance and transfer limits; it is not required reading for ordinary prompt creation.

## Local implementation

- `~/home_config/lisp/danbooru.el`: header and settings; `danbooru--parse`, `danbooru--flatten`, `danbooru--join`, legacy expansion, story validation/expansion, queue seeds, preview, and backend functions.
- `~/home_config/lisp/tests/danbooru-test.el`: existing examples and assertions for flattening, JSON, actor binding, variants, inheritance, and errors.
- `~/home_config/lisp/examples/manga.danbooru`, `danbooru-manga.md`, and `danbooru-explained.md`: usage examples and explanation, checked against source.
- `~/work/danbooru/tags/vocab/danbooru.csv`: 140,782 rows in the inspected snapshot; canonical tags and aliases checked directly. No corpus copy is bundled.

The source establishes prompt compilation behavior. It does not establish visual quality or prove the remote server's checkpoint and settings. The default `run-anima.sh` path and the older path mentioned in the header were absent. Research and validation did not call an image backend.

## Online sources and decisions

1. [OpenAI: build skills](https://learn.chatgpt.com/docs/build-skills) and [build plugin skills](https://developers.openai.com/plugins/build/skills).
   Use a directory with `SKILL.md`, required name/description frontmatter, a specific trigger, and linked references loaded as needed. Keep this skill instruction-only; the existing Emacs compiler already handles format validation. Creating it in the user's requested directory does not itself configure Codex discovery.

2. [CircleStone Labs: Anima model card](https://huggingface.co/circlestone-labs/Anima).
   Basis for the Anima-specific guidance in `SKILL.md` and the Gelbooru spelling exception in `tags.md`. Recheck the card for the exact checkpoint before changing settings. Do not transfer these controls to another generator automatically.

3. [Danbooru: how to tag](https://safebooru.donmai.us/wiki_pages/howto:tag), [tag groups](https://safebooru.donmai.us/wiki_pages/tag_groups), [composition](https://safebooru.donmai.us/wiki_pages/tag_group:image_composition), [hair](https://safebooru.donmai.us/wiki_pages/tag_group:hair), and [face tags](https://safebooru.donmai.us/wiki_pages/tag_group:face_tags).
   Describe observable content with established tags and distinguish composition, appearance, expression, and medium. Site tagging instructions describe image indexing, not guaranteed generation behavior. Vocabulary examples were also checked against the user's local CSV.

4. [NovelAI: tagging](https://docs.novelai.net/en/image/tags/) and [undesired content](https://docs.novelai.net/en/image/undesiredcontent/).
   Known tags can aid consistency; negative inputs target unwanted features. Its documentation explicitly makes tag-order effects dependent on model version. NovelAI braces, emphasis syntax, renamed tags, quality presets, and per-character features must not be assumed to work in Anima or this Emacs parser.

5. [Black Forest Labs: FLUX.2 prompting guide](https://docs.bfl.ai/guides/prompting_guide_flux2).
   Subject, action, style, and context provide a useful way to identify missing parts of a visual brief. The skill adds framing and attribute ownership as practical editorial checks. Those checks are a synthesis for this workflow, not evidence that FLUX-specific behavior, lengths, ordering, or parameter formats transfer to Anima.

The resulting method is to preserve the brief, choose concise visible attributes, use prose for relationships, compile the local format, and compare controlled revisions when images are available. No universal best prompt length, guaranteed ordering effect, or guaranteed anatomy fix is claimed.
