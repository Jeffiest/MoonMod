# Progress

- 2026-11-11: Orchestrator-and-workers setup created (CLAUDE.md, these three docs, builder and reviewer
  agents, the reflect skill). Same session: the first tools for the Bloodborne proof of concept (`tools/bb`).

## The proof of concept: a Bloodborne beast in the Dasher's place (Divine Beast Cave, `e06a`), on its own data

| Step | What | State |
|---|---|---|
| 1 | `tools/bb/BbModel`: the beast's model and textures out of the dump (`model.json`, `.dds`) | Written, **not built or run** (needs DSAnimStudio and a dump) |
| 2 | `tools/bb/model_gltf.py`: `model.json` to a skinned glTF | Done: its test passes, and its output imports into Blender 5.3 with the skin following the bones (made-up model) |
| 3 | `tools/bb/template_facts.py`: what a monster's pack and its export hold, as text | Done: its test passes, and it read one real export (Opar's `c07d.chr`) correctly. Not yet run on `e06a` |
| 4 | The beast's animations out of the dump (its `.anibnd.dcx`), into the glTF as actions | Not started. `tools/anim/reference` already decodes Elden Ring's the same way |
| 5 | Cut the beast down to what Dark Cloud holds (Blender): bones a skinned mesh, weights a vertex, triangles, picture sizes, motion length | Not started: the limits for a monster have to be read off `e06a` and the port first |
| 6 | Build a pack from the glTF alone: own frames, own bind pose, own weights, own motion file | Not started. See *What is known about step 6* |
| 7 | The monster around the pack: which motion numbers the AI plays, the frames a script names (damage and hit points), stats | Not started |
| 8 | The mod (`dc2tk mod-pack`, `monsters/<stem>/` or an override of `e06a`), seen on the cave's first floor | Not started |
| 9 | The beast's own sounds and AI | Later |

### What is known about step 6 (read in the source, nothing run)

- The toolkit's usual build keeps the template's skeleton: `from_gltf.rs` `import_gltf` replaces meshes by frame
  name and can add frames for new mesh nodes, no more.
- It also has a build from the glTF alone: `from_gltf.rs` `new_model` makes a frame for every node and weights a
  skinned mesh to its joints' frames, and `motions::new_motion` reads the glTF's animations. `models.rs` calls it for
  a pack added to a mod (`docs/guide/models.md` in dc1tk, "Add a new model pack").
- Not known: whether that path writes a pack Dark Cloud 1 loads (its guide is Dark Chronicle's), and the dc1tk in
  this workspace does not write Dark Cloud 1 skin weights at all (`docs/known-issues.md`). The first test of this
  route is a small made-up skinned model built that way and loaded in the game.

## Open checks, the user's to run (CLAUDE.md rule 6)

- Build `tools/bb` against DSAnimStudio and run `BbModel list` on the dump's `chr` folder (`tools/bb/README.md`).
  Wanted back: whether it builds, and the list, to choose the beast.
- `BbModel export` of the chosen beast, then `model_gltf.py`, then open `model.gltf` in Blender. Wanted back: does
  it look right, which way does it face, is it mirrored (weapon or asymmetry on the wrong side).
- Export the Dasher with the toolkit build that keeps skin weights (`docs/known-issues.md`) and run
  `template_facts.py` on it. Wanted back: its printed text. On the own-data route it no longer gives the skeleton
  to build on; it gives the sizes a monster's pack has in this game, and the frames and motion numbers its script
  uses.

## Next

- A session that can reach the dump, DSAnimStudio, the game's data and the toolkit build that keeps skin weights:
  every open check above waits on it.
- Step 6's first test (a made-up skinned model built from the glTF alone, loaded in the game), before any work on
  the beast depends on it.
- Get the toolkit's skin export and build into the dc1tk repository, so the pipeline does not depend on one
  machine's build.
