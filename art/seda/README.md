# Seda

The eighth playable hero: Seda, the swordsman of four hundred years ago, who went down after the Dark Genie and waits
in the Divine Beast Cave for a boy from Norune. How he plays and what is left to do is
[docs/SEDA_PLAN.md](../../docs/plans/SEDA_PLAN.md).

**He is made from his own model in the game** (pack `c07a`, from his floor 8 fight), fitted onto Toan's skeleton so he
plays Toan's motions and holds Toan's swords. On a machine with the DC1 toolkit and your disc's data:

```bash
python tools/chr/build_character.py retail <your data>/dun/mainchara --art art/seda   # his model into seda.blend
python tools/chr/build_character.py build  <your data>/dun/mainchara --art art/seda   # art/seda/build/c08d.chr
copy art\seda\build\c08d.chr mods\moonmod.roguelike\resources\seda\c08d.chr
```

`retail` finds his pack under the data folder (any `*c07a*.chr` with a skeleton, the largest; `--source <pack>`
names it), exports it, sets its bind pose, and runs `make_seda.py --retail` on it:

- **Fit**: his mesh scaled so his hips stand at Toan's, then each of his chain bones' part of the mesh turned and
  moved so that bone lies along Toan's bone of the same name, blended by his own skin weights. The weights carry over
  by name. A rigid mesh (a part hung on a bone) follows its bone. If his joints are not named as Toan's, he is
  scaled to Toan's height and weighted by distance instead, which works only if his bind pose has his arms out.
- **Pictures**: his own textures, through his own UVs, baked into the pack's four pages (`c08d02` head, `c08d03`
  torso and arms, `c08d04` waist, `c08d05` legs).
- Checked without the game: a test Seda grown a fifth with his arms raised, exported to glTF, came back on Toan's
  skeleton with his arms out and his bounds as before (to 0.01), his pictures intact. Not yet run on the real pack.

His retail export stays in `art/seda/build/` (git-ignored): it is the disc's data.

**The stand-in.** Before his pack was found, `make_seda.py` with no `--retail` made a look-alike from shapes (below);
it is what `seda.blend`, `textures/` and `previews/` hold until `retail` is run.

- `make_seda.py` (no `--retail`): makes the stand-in's model, paint and weights in `seda.blend`, then renders
  `previews/`. Shapes, colours and gear are in the script, so a change is an edit and a rerun:
  ```bash
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b art/seda/seda.blend --python art/seda/make_seda.py
  ```
  It also runs under the `bpy` module (Blender 5.2 as a Python package), with no GPU: the previews render with Cycles.
  - **Body**, one skin: pelvis, waist, a broad flat chest, shoulders, a narrow head with jaw, brow and nose, arms,
    gloved hands, legs and booted feet, fused by a voxel remesh and decimated to about 5,200 triangles.
  - **Gear** on it: the violet coat's skirt, open at the front and hemmed in silver; a high collar; a belt with a
    silver buckle; a two-plate steel pauldron on the left shoulder; white hair (a cap, a fringe, two side locks and a
    long fall down the back).
  - **Paint** by region (pale skin, red eyes, the coat's V over a grey shirt between silver edges, dark gloves and
    trousers, leather boots), baked by Cycles with cloth grain, hair streaks and ambient occlusion, at 1024 and
    scaled to the pack's 256 x 256: `c08d02` head and hair, `c08d03` torso and arms, `c08d04` the gear, `c08d05`
    legs and boots.
  - **Weights** to the 20 chain joints. The skirt follows the hips and, lower down, the thighs; the hair's fall
    follows the head at its top and the chest at its end.
  - About 7,100 triangles in all.
- `seda.blend`: made from `art/opar/opar.blend` (Toan's skeleton and the template reference). `proportions.json` is
  empty, so the script takes Opar's wider hips back out: Seda stands on Toan's own skeleton.
- `textures/`: the baked pictures. `previews/`: front, side and back renders.

The Gauntlet registers him from `mods/moonmod.roguelike/resources/seda/c08d.chr` when it loads, right after Opar.
