# Gauntlet log

Passes of the gate loop in [GAUNTLET.md](../../../GAUNTLET.md), newest first.

## 2026-10-28 — G0 automated on the new master, Windows

The patch was ported to Chronicle `9418a550` (master after `d3666bcb` forked the game into `port/src/game`) and
Kazarov `b619d1a`. Both patches apply cleanly to an untouched checkout. Built with `build.bat windows-x64-release`
(its pinned llvm-mingw, Rust and FFmpeg), then `DC_BUILD_TESTS=ON`.

| Check | Result |
|---|---|
| `darkcloud`, `darkcloud_tests`, `dcdata` build | Clean |
| Engine filter (`MoonModTitleModes*:MoonModRoguelike*:MoonModWorldTransition*`) | **9 passed, 0 failed** |
| Full suite, patched | 818 tests: 794 passed, 17 skipped, 7 failed |
| Full suite, baseline (unpatched `9418a550`) | 683 passed, 18 failed |
| Failures on the patched build that the baseline passes | **None** |
| Lua harness | 62/62 and 38/38 |

The 7 patched failures all fail on the baseline too: three `PlatformMc` seek tests, two `LocalizeLanguages` export
tests, `LocalizeOptions.TheExportListsTheOptionStringsWithTheShippedText` and `DataRead.MetadataSnapshotsStayFresh
WhenDisabled`. The baseline's other 11 (`PlatformPad.InputBindings`, 10 `PlatformMouseLook.*`) pass with the patch.

Found and fixed during the port, beyond moving code:

- `LocalizeOptions.ShippedTranslationsHaveExactlyTheCodesKeys` (failing on the old base too): the patch shipped
  translations for the aerial and fit-to-screen dungeon map but no option rows. Both are now Options > Game rows.
- The enlarged item tables (32 mod weapon slots) leaked into upstream's new item documents and read `PriceList` past
  its end. The documents now cover the retail rows only, and `PriceList` has room for the mod slots.
- `scanRoomInfoWork` was 16 x 16 while the room scan indexes up to 48 x 48 on mod floors; it is now sized and reset
  for the full room area.
- `MoonModLocationsApi` left the data reader indexed on a deleted folder, which broke a later localization test.
- Upstream's native autosave writes nothing during a sandbox session, so a run never saves.

Not carried over: the floor-build diagnostics (`DC_MAZE_DUMP`, the pit report and the maze ground probe). They
only logged.

## 2026-10-28 — G0 automated, Windows (on `6ec3b808`, before the port)

Chronicle `6ec3b808` + `moonfactory-chronicle.patch` + `moonfactory-kazarov.patch` (both applied cleanly with
`apply-moonfactory.ps1`), MoonFactory at `bc7d524`. Built in `E:\Gauntlet-build` with llvm-mingw (clang, 2026-09-22
ucrt), Ninja, RelWithDebInfo, SDL 3.4.18, Vulkan SDK 1.4.363, on a machine with a GPU.

| Check | Result |
|---|---|
| Patched `darkcloud_tests` build | Clean |
| Engine filter (`MoonModTitleModes*:MoonModRoguelike*:MoonModWorldTransition*`) | **9 passed, 0 failed** |
| Full suite, patched | 622 tests, 104 suites: 607 passed, 8 skipped, 7 failed |
| Full suite, baseline (unpatched `6ec3b808` + Kazarov `a78762c` only, since plain `6ec3b808` does not build) | 522 tests, 69 suites: 494 passed, 8 skipped, 20 failed |
| Failures on the patched build that the baseline passes | **None** |

The 7 patched failures, all failing identically on the baseline: `PlatformMc.SeekMovesPositionForReadAndWrite`,
`PlatformMc.SeekRejectsBadFileAndOrigin`, `PlatformMc.EndReturnsZeroAndKeepsOpenFiles`,
`PathsXdgDarkcloud.DarkcloudNamesTheDirectoryToExtractTo`, `LocalizeOptions.ShippedTranslationsHaveExactlyTheCodesKeys`
(fr_fr carries `dungeon_aerial_map` and `fit_dungeon_map` keys the code lacks), and
`AreaCard.TranslatedLettersUseTheWholeRetailBox` / `TranslatedWordsKeepTheRetailBoxAlignment`. The baseline's other 13
(`PlatformPad.InputBindings`, 10 `PlatformMouseLook.*`, 2 `DataRead.Paths*`) pass with the patch.

Verdict: G0 automated is **green**. G0 playtest is next (title rows on PAL, the mode screen, Circle back, mod off), with
`Dark Cloud (Europe) (En,Fr,De,Es,It).iso`. NTSC checks are dropped.

Before the playtest: Chronicle master moved 74 commits past `6ec3b808` (to `9418a550`), including `d3666bcb`, which
forks the game into `port/src/game` and removes `PORT_OVERRIDE`. The patch is being ported to it, and G0 automated
re-runs on the new base.

## 2026-10-28 — Lua harness, Windows (provisional)

Branch `claude/roguelike-gauntlet-continue-w0c9ci` at `bc7d524`. Vendored Lua 5.5.1 built with LLVM clang.

| Check | Result |
|---|---|
| `test_runs.lua` | 62 passed, 0 failed |
| `test_standalone.lua` | 38 passed, 0 failed |
| Engine filter (`MoonModTitleModes*:MoonModRoguelike*:MoonModWorldTransition*`) | Not run on Windows yet (last run: Linux, clang 18, 9 passed) |
| Playtest | Not started |

Verdict: no gate signed. G0 is next: apply the Chronicle patch, run the engine filter, then the title-screen playtest.
