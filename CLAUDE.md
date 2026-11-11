# MoonMod

Read this first, every session, then `docs/progress.md`, `docs/decisions.md` and `docs/known-issues.md`.

## What this is

MoonMod holds MoonFactory, the mod framework built into the PC ports of Dark Cloud (Chronicle) and Dark
Chronicle (Chronicle Two), with the mods, tools and docs built on it. It is the hub of a five-repository
workspace: the toolkit that converts Dark Cloud's files (dc1tk), two forks of the Dark Cloud port
(Chronicle, DC_Web) and a Bloodborne decompilation and runtime (Paleblood).

Current goal (2026-11-11): a proof of concept that puts a Bloodborne enemy, read from the user's own dump,
into Dark Cloud's Divine Beast Cave as a full replacement for one of its monsters (the Dasher), on the
beast's own skeleton, motions and textures, by a route that can be repeated for other assets.

## Rules

1. The main session is the orchestrator. It plans, writes briefs and checks results. It doesn't do bulk
   work itself when a worker can do it.
2. Workers are subagents on Haiku (`builder`, `reviewer`). Every brief states the goal, the files to read,
   and a "Done when:" check that can be run or seen: a test that passes, a file that exists, a number on
   the screen.
3. Before accepting any worker's output, the orchestrator runs the check itself. If it fails, the work goes
   back to the worker with the failure attached. A worker's report is never passed on unchecked. Where a
   worker's test only reads back what its own code wrote, the orchestrator adds one check on input the
   worker didn't make.
4. Start of every session: read this file and the three docs. End of every session: update
   `docs/progress.md`, add new decisions and gotchas, and propose skill edits with the evidence from the
   session (`/reflect`). The user approves them before they are applied.
5. Nothing from Bloodborne goes into any repository, raw or converted: models, textures, animations,
   decompiler output. Tools read the user's own dump and write to a cache or build folder outside git, as
   `tools/anim/reference` does. Each repository's own game-data rule still applies.
6. A check that needs game data the machine doesn't have is not a pass. The brief gives the exact command
   and what should be seen, and the item stays open in `docs/progress.md` until the user has run it.

## Where everything lives

| Path | What |
|---|---|
| `CLAUDE.md` | This file |
| `docs/progress.md` | Where we are: done, next, a dated line per session |
| `docs/decisions.md` | What's settled, with the date and why |
| `docs/known-issues.md` | Gotchas and their fixes |
| `.claude/agents/` | `builder` (writes code to a brief), `reviewer` (checks a diff against a brief) |
| `.claude/skills/reflect/` | End-of-session improvement loop |
| `ports/` | MoonFactory as each game builds it: one patch per port against a named upstream commit |
| `mods/`, `examples/` | Bundled mods and small mods to copy from |
| `docs/` | Modder's guide, API reference (`docs/api/`), asset guides, plans (`docs/plans/`) |
| `tools/chr/` | Character packs (`.chr`) built from glTF on a template pack; modelling rules in its README |
| `tools/anim/` | Motion tools; `reference/` reads FromSoftware animations from the user's own install |
| `tools/bb/` | Bloodborne model out of the user's dump (`BbModel`), to glTF (`model_gltf.py`), and a monster pack's facts (`template_facts.py`); its README has the commands |
| `tools/stb/` | Monster and event script disassembler and patcher |
| `tools/tests/` | Tests for the tools and examples |
| `art/` | Sources for characters the mods add (Opar, Seda) |
| `src/`, `include/`, `vendor/` | Standalone copy of the shared runtime; Lua 5.5.1 |
| `../dc1tk` | Dark Cloud toolkit (Rust, `src/`). `DC1.md` has the commands: `model-export`, `model-build`, `mod-pack` with `monsters/<stem>/` for a new enemy |
| `../Chronicle` | Fork of the Dark Cloud decompilation and PC port that MoonFactory patches |
| `../DC_Web` | Chronicle import with MoonMod's mods built in, co-op and a web build; `docs/MODEL_FRAMEWORK.md` |
| `../Paleblood` | Bloodborne decompilation and native runtime; `STATUS.md`, `NEXT.md`, `QUIRKS.md`. No asset readers |

## Checks

    python -m unittest discover -s tools/tests -p "test_*.py"
    python tools/pack/build_pack.py --check
    python tools/gen_api_reference.py --check
    python tools/check_docs.py
    (cd ../dc1tk/src && cargo test --release)
