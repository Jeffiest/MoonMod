# Testing mods

A mod is tested in layers, from fast checks run outside the game to a human playing it. Each layer catches what the
one before can't. The Gauntlet uses all of them. Its harness plays hundreds of whole runs in seconds, and the game
itself confirms the rest.

| Layer | Runs | Catches | Speed |
| --- | --- | --- | --- |
| 1. Fake adapter | Your mod's Lua against a fake `game.*` | Logic, state, wrong fields, bad call order | Seconds |
| 2. Recording stub | Other mods' Lua, recording their calls | Mods sitting out each other's modes | Seconds |
| 3. Engine tests | The engine's C++ (GoogleTest) | New operations: contracts, thousands of floors | Minutes |
| 4. Headless game | The real game, scripted input, screenshots | Real data, timing, what it looks like | A minute a run |
| 5. Playtest | A person, with a checklist | Feel, balance, anything the scripts missed | As long as it takes |

## 1. The fake adapter

`tools/tests/roguelike/fake_game.lua` is a fake Chronicle adapter. It keeps a little world (where the player is,
party HP, items, weapons, monsters, registered floors), answers the `game.*` calls the Gauntlet makes, and emits
events. `tools/tests/roguelike/test_runs.lua` loads the real `mods/moonmod.roguelike/main.lua` against it and plays
scenarios: start a run, clear floors, take gates, kill Wardens, die, reload.

Run it from the repository root with any Lua 5.4 or newer:

```bash
lua tools/tests/roguelike/test_runs.lua
lua tools/tests/roguelike/test_standalone.lua
```

With no Lua installed, build the vendored one once (any C compiler; this uses clang):

```bash
cd vendor/lua-5.5.1/src && clang -O2 -D_CRT_SECURE_NO_WARNINGS -o <somewhere>/lua.exe $(ls *.c | grep -v '^luac.c$')
```

A scenario reads like play:

```lua
-- The Rest floor between biomes, in the next biome's dungeon
check(S.dungeon == 1 and S.floor == 17, "Warden death moved the run to Wise Owl Forest's Rest floor")
check(#S.monsters == 0 and S.modifiers.chests == -100 and S.rest_built, "a rest floor: nothing to fight, no chests")
check(S.npc and S.npc.id == "gaffer", "Gaffer waits there")
S.hp.toan = 5; S.player_pos = {x = 960, y = 0, z = 600}; S.tick(30)
check(S.hp.toan == S.max_hp.toan, "the spring heals the party")
S.hp.toan = 5; S.tick(30)
check(S.hp.toan == 5, "once a visit")
S.exit_gate(); S.tick(20)
check(S.floor == 18 and S.storage.run.slot == 1, "its exit gate leads on to 2-1")
```

**Keep the fake honest.** A fake that accepts anything proves nothing. Each fake operation checks its fields the way
the real handler does and refuses what it refuses:

```lua
set_rest_room = function(a)
  for k in pairs(a) do assert(k == "enabled", "set_rest_room field " .. k) end
  assert(type(a.enabled) == "boolean", "set_rest_room enabled")
  S.rest_room = a.enabled
  return {enabled = a.enabled, state = "none"}
end,
```

When you add an engine operation, add it to the fake in the same change, with the same checks and result shape.

**For your own mod**, copy the approach. Write a small fake of the operations you call, load your `main.lua` with
`moonmod`, `game` and `moonmod.on` set up as globals, step frames by calling your `game.tick` callbacks, and assert on
the fake world. `test_runs.lua` shows how to read setting defaults from `mod.json` and boot the mod under different
settings.

## 2. The recording stub

`tools/tests/roguelike/test_standalone.lua` loads RPG, Ascension and Dungeon+ against a stub that records every call
as `"namespace.fn"` and answers a few with game-shaped data. It checks that each mod stands down while a Gauntlet
session is running (formulas back to x1, no tuning, no bars) and comes back after it. Use the same idea to check
that your mod leaves other mods' modes alone.

## 3. Engine tests

Engine changes get GoogleTest cases in the Chronicle tree (`port/src/tests/moonmod_*_test.cpp`). See
[Extending the engine](EXTENDING_THE_ENGINE.md#8-test-it).

```powershell
darkcloud_tests.exe --gtest_filter=MoonMod*                 # the MoonFactory tests
darkcloud_tests.exe --gtest_filter=DungeonReach.*           # thousands of generated floors, each checked
```

Some tests fail on an unpatched build depending on the machine (GPU, OS). Compare against the unpatched build on the
same machine: a change must add no new failure.

## 4. Headless game runs

The game runs without a window, driven by a script, and writes screenshots:

```powershell
darkcloud.exe --data <extracted game data> --save <test save folder> --headless --width 960 --height 720 `
  --frames 2000 --input script.txt --screenshot shot.png --screenshot-at 900,1500,1990 2> run.log
```

- **`--save` a test folder, never the player's.** Its `mods` folder holds the mods for the run, and its `moonmod`
  folder holds the profile (which mods are on) and each mod's storage. Keep a clean copy and restore it before each
  run, because a run changes storage (a run in progress, unlocks, records) and the next run starts from it.
- **`--input`** drives the pad. Each line is a frame number and the buttons held from then on. A line with no button
  releases everything, and a press needs a later release line:

  ```
  0
  200 start
  204
  700 down
  704
  800 cross
  804
  ```

  Buttons are `cross circle square triangle start select l1 r1 l2 r2 l3 r3 up down left right`, plus `key:NAME`,
  mouse and stick values. The full format is in Chronicle's `docs/PC.md` ("Scripted input").
- **`--screenshot-at`** writes `shot_<frame>.png` at each listed frame. Look at them. A screenshot shows what a log
  line can't: a door in the wrong place, a panel cut off, a model that didn't load.
- **Logs.** Mod log lines arrive on standard error as `moonmod[level][mod id]: message`. Redirect them to a file.

### Driver mods

Pressing buttons on a timer is fragile for anything long. A **driver mod** is a small test-only mod placed beside the
mod under test. It calls the API to move the test along and logs what it sees. The Gauntlet's driver visits every
run floor in order with `world.transition`, waits on each, and logs the arrival, the room count, the enemies left and
the player's position:

```lua
moonmod.on("game.tick", function(e)
  if e.frame % 15 ~= 0 then return end
  local world = call(game.world.get)
  if not (world and world.context == "dungeon") then return end
  -- on arrival: log it; after 300 frames: log the settled floor; after DWELL frames: transition to the next floor
end)
```

Grep the log for `DRIVER` lines afterwards. Combine a driver with the engine's test hooks (`DC_REST_TEST=stairs`
stands the player on the rest floor's stairs) to reach a moment directly instead of walking there.

### Things that bite

- **Keep long scripts kind to the run.** Repeated attacks wear weapons, and in the Gauntlet a broken weapon ends the
  run. A driver that attacks for minutes should repair (`weapons.durability_set`) or it will test the wrong thing.
- **Shuffled content looks like a bug.** The Gauntlet's shuffled floors may put a floor in another dungeon. Read the
  plan before calling a destination wrong.
- **Engine `printf` output is lost if the process is killed** before it flushes. Let runs end by `--frames`, or flush.
- **A call that returns success may still have done nothing.** `items.give` returns success after adding 0 to a full
  bag. Check the effect, not just the return.
- **Floors are reported before they are built.** On arrival, wait for the floor's state (`rest_room_get`,
  `warden_room_get`) before acting on its layout.

## 5. Playtests

Write the checklist down before playing: each line something a person can see and tick, with what passes. The
Gauntlet's gate loop ([GAUNTLET.md](../../GAUNTLET.md)) does this per feature, with results in
`tools/tests/roguelike/gauntlet-log.md`. A feature isn't done until its line is ticked in the real game. Three
failures on the same line mean the design is wrong, not the code.

Play from a copy of the game that matches what you just built: the new `darkcloud.exe` and the new mod files. A
playtest of last week's build tests nothing.
