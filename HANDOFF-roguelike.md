# Handoff: Dark Genie's Gauntlet (roguelike title mode)

Branch: `roguelike-gauntlet`. A roguelike game mode reached from Chronicle's title menu, built from a design doc for a
Dark Cloud roguelike: five biomes of three floors and a Warden, Cursed Gates, fast ABS, Shatter, an in-run Diorama,
drafted allies, and Moon Shards that buy Norune Eternal unlocks. A run belongs to no save slot and never saves.

## What is where

| Path | What |
| --- | --- |
| `mods/moonmod.roguelike/` | The Lua mod (`main.lua`), its manifest, and its player guide (`README.md`). The guide also maps the design doc to what was built and lists the API limits. |
| `ports/chronicle/moonfactory-chronicle.patch` | Refreshed engine patch. It adds **title modes and sandbox sessions** (`title.*`, `session.*`, `game.title.*` and `game.session.*` events) on top of the existing MoonFactory patch. Apply it with `ports/chronicle/apply-moonfactory.ps1` to Chronicle `6ec3b808`. |
| `docs/API.md` | The section "Chronicle title modes and sandbox sessions" documents the new API. |
| `tools/tests/roguelike/` | Lua harness: a fake adapter plus 62 checks that play whole runs. Run it with `lua tools/tests/roguelike/test_runs.lua` (Lua 5.4+). |
| `mods/moonmod.hub/` | Two new quick links to the Gauntlet. |

The engine code inside the patch (in a Chronicle checkout):

| File | What |
| --- | --- |
| `port/include/moonmod/title_modes.hpp`, `port/src/moonmod/title_modes.cpp` | Registry, screen state, session state. |
| `port/src/moonmod/chronicle_adapter.cpp` | `session.start` and `session.finish`, party setup (`StartPendingChronicleSandbox`), the exit redirect (`RedirectChronicleSandboxMapJump`), `cur_georama` on each dungeon entry, `save.slot_id` nil during a session. |
| `port/src/title/titleloop.cpp` | Extra title rows, mode screen steps 40 and 41, drawing with `UI::Label` and `UI::Window`, `TitlePortReopenMode`. |
| `port/src/gameloop.cpp` | `StartSandboxGame` (title result 10), the redirect in `GameFollowMapJump`, the end of a session on a battle-menu load or a developer jump. |
| `port/src/dun/movechara.cpp` | A game over is noted as a defeat. |
| `port/src/tests/moonmod_title_modes_test.cpp` | Engine tests. |
| `port/src/tests/moonmod_roguelike_package_test.cpp` | Loads this mod through the real Lua runtime (it expects the MoonFactory checkout beside Chronicle, named `MoonFactory`). |

## Verified (Linux, clang 18, no game data, no GPU)

- The patched port builds.
- `darkcloud_tests --gtest_filter='MoonModTitleModes*:MoonModRoguelike*:MoonModWorldTransition*'` passes: 9 tests.
- The full suite: 101 suites pass. The 10 that fail (Gfx*, PlatformArena, PlatformMc, TexDecode, LocalizeOptions,
  CustomShopTest) fail identically on the untouched baseline, because this machine has no GPU.
- The Lua harness passes all 62 checks, and the manifests validate against `manifest.schema.json`.
- A separate code review of the engine changes was done, and its findings are fixed and tested.

## Not verified: needs the real game (disc image and a GPU)

1. Title visuals on PAL (480) and NTSC (448): the extra row under OPTION at y 376, the copyright banner moved down
   (clamped to `SCREEN_HEIGHT - 48`), and the mode screen layout and fades.
2. Starting straight into a dungeon from a fresh save: the native dungeon entrance with no story progress.
3. That the native exit on a registered floor loads the next registered floor, and what the Warden floor's exit does
   if it is reached before the Warden dies.
4. The source floors in `BIOMES` (`main.lua`) hold no scripted events.
5. Weapon wear per hit against the *Shatter at durability* setting (default 3).

## Known limits and next ideas

- The mouse cannot click entries on the mode screen (keyboard and controller only).
- Sessions use `session.finish` (not `end`, which is a Lua keyword).
- The canonical runtime sources in `src/` lag the port copies. The title-mode code lives only in the Chronicle patch.
  Chronicle Two has no title modes.
- RPG and Ascension weapon loot rolls never apply: `game.item_picked_up` gives `character` as a number (0-5), but those
  mods compare it with ids like `"toan"`. This is a pre-existing bug and is not fixed here.
- `docs/API.md` is stale in two places: `render.bar_register` takes `{id, label, current, max}`, and `ui.notify` notices
  also draw over gameplay.

## Linux build notes, if you build there

These were needed besides the repo: SDL3, Vulkan headers at 1.4 or newer plus `libvulkan.so`, `glslangValidator`,
nlohmann_json 3.12 and GoogleTest, all built into a prefix. The vendored `dr_wav.h`, `dr_flac.h`, `stb_vorbis.c`,
`stb_truetype.h` and `stb_image.h` (at the pinned commits) go in `<Chronicle>/audio_decoders/`. With clang older than
20, configure with `-DCMAKE_CXX_FLAGS="-Wno-return-type -Wno-unknown-warning-option"`.
