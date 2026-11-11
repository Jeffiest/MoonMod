# Progress

- 2026-11-11: Orchestrator-and-workers setup created (CLAUDE.md, these three docs, builder and reviewer
  agents, the reflect skill). Same session: the first tools for the Bloodborne proof of concept (`tools/bb`).

## The proof of concept: a Bloodborne beast in the Dasher's place (Divine Beast Cave, `e06a`)

| Step | What | State |
|---|---|---|
| 1 | `tools/bb/BbModel`: the beast's model and textures out of the dump (`model.json`, `.dds`) | Written, **not built or run** (needs DSAnimStudio and a dump) |
| 2 | `tools/bb/model_gltf.py`: `model.json` to a skinned glTF | Done: its test passes, and its output imports into Blender 5.3 with the skin following the bones (made-up model) |
| 3 | `tools/bb/template_facts.py`: what the Dasher's pack and its export hold, as text | In review |
| 4 | Fit the beast to the Dasher's skeleton (Blender): pose, scale, weights, triangle budget, textures | Not started: needs step 3's output for `e06a` |
| 5 | Build the pack and the mod (`dc2tk model-build`, `mod-pack`), see it on the cave's first floor | Not started |
| 6 | The beast's own animations and sounds | Later |

## Open checks, the user's to run (CLAUDE.md rule 6)

- Build `tools/bb` against DSAnimStudio and run `BbModel list` on the dump's `chr` folder (`tools/bb/README.md`).
  Wanted back: whether it builds, and the list, to choose the beast.
- `BbModel export` of the chosen beast, then `model_gltf.py`, then open `model.gltf` in Blender. Wanted back: does
  it look right, which way does it face, is it mirrored (weapon or asymmetry on the wrong side).
- Export the Dasher with the toolkit build that keeps skin weights (`docs/known-issues.md`) and run
  `template_facts.py` on it. Wanted back: its printed text.

## Next

- Step 4's design, once the Dasher's facts are in: whether its body is skinned or rigid pieces decides how the
  beast's mesh is cut and weighted.
- Get the toolkit's skin export and build into the dc1tk repository, so the pipeline does not depend on one
  machine's build.
