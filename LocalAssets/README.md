# LocalAssets (not committed)

Put assets you own a copy of here to bundle them into **local** builds only.
Everything in this folder except this README is git-ignored, so it never
reaches the public repo or CI releases.

- `LocalAssets/Alcove/` — Alcove's `*.caf` / `*.m4a` sounds and `airpods-*.mp4`
  videos (for example copied from your own `/Applications/Alcove.app/Contents/Resources`).

A build phase copies `LocalAssets/Alcove/` into `Foyer.app/Contents/Resources/AlcoveAssets/`
when it exists. At runtime Foyer prefers, in order: bundled `AlcoveAssets/`,
an installed Alcove.app, then Foyer's own sounds / SF Symbols.
