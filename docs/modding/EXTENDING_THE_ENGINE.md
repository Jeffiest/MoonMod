# Extending the engine

Lua mods can only do what the `game.*` API offers. When a mod needs something more, such as a floor with a fixed
shape, a sealed boss room, a sixth-plus party member or more monsters than Dark Cloud allows, the answer is to add it
to the engine as a new operation. The Gauntlet's rest floors, Warden rooms, shortcut doors, run menu, choice panels,
new moves and extra playable characters were all added this way, and each became a general operation any mod can use.

This page shows how to make such a change, using `dungeons.set_rest_room` as the worked example.

## The rule: raise the limit, don't obey it

Dark Cloud was written for a PS2 with fixed pools: 15 monsters on a floor, a 20 x 20 floor grid, a few rooms and
chests, six characters, set item and weapon tables. The PC port has no such limits. When a design runs into one,
raise it in the engine instead of shrinking the design. Already raised:

| Limit | Retail | Now |
| --- | --- | --- |
| Monster slots (`MONSTOR_SLOT_MAX`) | 16 | 256 |
| Floor grid (`DNG_GRID`) | 20 x 20 | 48 x 48 |
| Rooms per floor (`DNG_ROOM_MAX`) | 16 | 64 |
| Chests (`DNG_BOX_MAX`) / event records (`DNG_EVENT_MAX`) | 24 / 48 | 64 / 384 |
| Georama plots | retail's | 56 |
| Weapon slots | retail's | 32 more after retail's (items 377-408) |
| Playable characters (`CHARA_MAX`) | 6 | 16 (6 saved + up to 10 registered) |

The raised values sit under `#ifdef PORT` with the retail values kept in the `#else` branch, so it is plain which is
which (`port/include/game/dungeonmap.hpp` is an example).

Raise a limit **without changing the save format**. The save holds fixed-size arrays, and old saves must load. The
extra playable characters show how: the save's per-character arrays became `CharaSlots<T, Field>`, laid out exactly
as the game's `T[6]` (checked with `sizeof` asserts), with indexes 6-15 stored outside the save.

## Where the engine code is

The engine is the [Chronicle](https://github.com/TheMoonPeople/Chronicle) PC port at the commit in
[`ports/chronicle/CHRONICLE_COMMIT`](../../ports/chronicle/CHRONICLE_COMMIT), with
[`ports/chronicle/moonfactory-chronicle.patch`](../../ports/chronicle/moonfactory-chronicle.patch) applied. Set up a
working tree once:

```powershell
git clone --recurse-submodules https://github.com/TheMoonPeople/Chronicle.git
.\MoonFactory\ports\chronicle\apply-moonfactory.ps1 -Chronicle .\Chronicle
```

The parts you will touch:

| Path | What it holds |
| --- | --- |
| `port/src/moonmod/api.cpp` | The operation and event **catalog**: path, domain, phase, permission, description |
| `port/src/moonmod/chronicle_adapter.cpp` | The Chronicle **adapter**: each operation's handler, dispatch, unload clean-up, events |
| `port/src/moonmod/*_moonmod.cpp`, `dungeonmap_layout.cpp`, `exit_room.cpp`, ... | Game-side helpers for bigger features |
| `port/include/moonmod/game_hooks.hpp` | The hooks the game's own code calls into MoonFactory |
| `port/src/game/`, `port/include/game/` | Dark Cloud's code (the port's fork). Edits here are hook calls and raised limits, each marked with a comment |
| `port/src/tests/moonmod_*_test.cpp` | Engine tests (GoogleTest) |
| `port/src/moonmod/lua_runtime.cpp`, `runtime.cpp` | The Lua host and shared runtime. Rarely changed for a feature |

Build with Chronicle's own scripts (`build.bat windows-x64-release`). The tests are the `darkcloud_tests` target,
built when the CMake option `DC_BUILD_TESTS` is `ON`:

```powershell
cmake --build port\build\windows-x64-release --target darkcloud darkcloud_tests
port\build\windows-x64-release\darkcloud_tests.exe --gtest_filter=MoonMod*
```

## Design the operation first

Write the [API map](../API.md) entry before the code. If it is awkward to explain, it will be awkward to use. The
habits the existing operations share:

- **General, not mod-specific.** `set_rest_room` builds "a rest layout", not "the Gauntlet's floor between biomes".
  The mod decides when to use it, what the spring does and where the stairs lead.
- **A request for what comes next.** Floor operations change the floors *built from then on*, so a mod sets them in
  `game.dungeon.generating` and nothing changes under the player's feet.
- **Owned.** Record which mod asked. If two mods can't share it, refuse the second with a clear message. Undo it
  when the owner unloads.
- **Strict about input.** Accept one table, reject unknown fields by name, check every type and range, and say what
  was wrong. A typo in a mod should fail loudly, not be ignored.
- **Readable back.** Pair a setter with a getter (`rest_room_get`) that reports state in API terms (world units, ids),
  so mods and tests can see what the engine did.
- **Events for things the player does.** If the mod must react (the player walked into the room, answered the
  panel), publish an event to the owner rather than making the mod poll.
- **Inert when unused.** With no mod asking, the game must behave exactly as before.

## Anatomy of an operation: `dungeons.set_rest_room`

### 1. Catalog it (`api.cpp`)

Each operation is one row: path, domain, name, phase, permission and description. Events have rows of their own.

```cpp
{"dungeons.set_rest_room", "dungeons", "set_rest_room", "simulation", "game.write",
 "Build new Chronicle floors as rest floors: a hall with a healing spring and an antechamber with the back floor's "
 "stairs, joined by the corridor that holds the way in and the exit."},
{"dungeons.rest_room_get", "dungeons", "rest_room_get", "simulation", "game.read", "..."},
```

The permission named here is the one the runtime checks before your handler runs.

### 2. Mark it supported, and dispatch it (`chronicle_adapter.cpp`)

The adapter has a list of the operation paths it supports. `moonmod.api.supports` and the verifier read it. Add the
path there, then add one line to the dispatch:

```cpp
if (operation.path == "dungeons.set_rest_room") return SetRestRoom(mod_id, args);
if (operation.path == "dungeons.rest_room_get") return {ApiCallStatus::Ok, RestRoomJson(), {}};
```

### 3. Write the handler

Arguments arrive as a JSON array of the Lua call's positional arguments. Validate them completely, check ownership,
change the engine state, and return the new state:

```cpp
std::string g_rest_room_owner;

ApiCallResult SetRestRoom(std::string_view owner, const Json &args) {
    if (!args.is_array() || args.size() != 1 || !args[0].is_object()) return Invalid("expected {enabled = boolean}");
    for (auto field = args[0].begin(); field != args[0].end(); ++field) {
        if (field.key() != "enabled") return Invalid("dungeons.set_rest_room received an unsupported field: " + field.key());
    }
    if (!g_rest_room_owner.empty() && g_rest_room_owner != owner) return Failed("another mod already builds rest floors");
    if (!args[0].contains("enabled") || !args[0]["enabled"].is_boolean()) return Invalid("enabled must be a boolean");
    const bool enabled = args[0]["enabled"].get<bool>();
    DngRestRoomEnabled = enabled ? 1 : 0;              // read by the floor builder
    if (enabled) g_rest_room_owner = std::string(owner);
    else g_rest_room_owner.clear();
    return {ApiCallStatus::Ok, RestRoomJson(), {}};
}
```

Remember that an empty Lua table arrives as an empty JSON **object**. If a field is a list, accept `{}` as an empty
list, or document that mods should leave the field out.

### 4. Release it on unload

The adapter's unload path runs for each mod as it unloads. Undo everything the mod owned there:

```cpp
if (g_rest_room_owner == mod_id) {
    g_rest_room_owner.clear();
    DngRestRoomEnabled = 0;
}
```

### 5. Do the game-side work

The feature itself lives beside the game code it changes. For rest floors, `dungeonmap_layout.cpp` builds the two
rooms and the corridor when `DngRestRoomEnabled` is set, places the native spring, entrance, exit and stair parts,
and records where they went (`DngRestSpringX`, `DngRestStairsX`, `DngRestRoomSeed`) for the getter.

When the game's own code must call into MoonFactory, declare a hook in `game_hooks.hpp`, define it in a `moonmod`
file, and call it from the game unit with a short comment. Keep edits inside `port/src/game` small: a call, a
raised constant, a branch on a MoonFactory flag. The logic belongs in `moonmod`.

### 6. Publish events to the owner

```cpp
SharedRuntime().PublishToMod(owner, "game.dungeon.backroom", {{"entered", index == 0}, {"frame", SharedRuntime().Frame()}});
```

Add a catalog row for the event in `api.cpp` with a one-line description of its payload.

### 7. Add a test hook if it is hard to reach in game

Some things take minutes of play to reach: a particular room, a trigger, a boss. The adapter has environment-variable
hooks that put the player there in a test run, inert unless the variable is set:

| Variable | Does |
| --- | --- |
| `DC_REST_TEST=spring\|stairs\|gate` | Stands the player at the rest floor's spring, stairs trigger or exit trigger, once per floor |
| `DC_WARDEN_VISIT`, `DC_WARDEN_CHASE` | Walks into the Warden room, or makes the Warden chase |
| `DC_EXIT_ROOM_TEST`, `DC_BACKROOM_TEST`, `DC_SHORTCUT_VISIT` | The exit room, back-floor stairs, shortcut doors |
| `DC_REACH_SEEDS`, `DC_REACH_DUMP` | How many floors `DungeonReach.*` walks; print one floor's grid |

Stand the player on the event's own trigger position, not the centre of the cell. Dark Cloud's triggers are small and
sit off-centre (see [Dark Cloud engine notes](DARK_CLOUD_NOTES.md#map-events-and-triggers)).

### 8. Test it

Add GoogleTest cases in `port/src/tests/`:

- **The contract**: bad arguments are refused with their message, a second owner is refused, the getter reports the
  state, unloading releases it.
- **The behaviour**: for floor features, build many floors from fixed seeds and check every one. The rest-floor test
  builds 200 floors (5 dungeons x 40 seeds) and checks two rooms, one of each stair, one spring, no pillars, parts in
  the right cells, and that the exit can be reached.

Run the whole suite and compare it with the unpatched build on the same machine. Some tests fail on the baseline
depending on the machine, so judge by "no new failures", not by a fixed count.

### 9. Document it, and teach the fake game

- Add the operation to [docs/API.md](../API.md), in the section for its domain, with an example call, every field
  and its limits, what the getter returns, the events, the one-owner rule and any test hook.
- Add it to the fake adapter in `tools/tests/roguelike/fake_game.lua` with the same field checks and result shapes,
  so mod tests catch a misuse before the game does (see [Testing mods](TESTING.md)).

### 10. Ship it: regenerate the patch

The deliverable is the patch. Regenerate it from the working tree against the base commit (Kazarov, the renderer
submodule, has its own patch):

```bash
git -C Chronicle diff 9418a550 -- . ':(exclude)tools/kazarov' > MoonFactory/ports/chronicle/moonfactory-chronicle.patch
```

Then check it applies to a clean checkout of the base commit:

```bash
git -C patchcheck apply --check ../MoonFactory/ports/chronicle/moonfactory-chronicle.patch
```

`python tools/make_release.py` builds the release folder (the changed Chronicle files, already patched, plus the
bundled mods).

## Working with others on one engine tree

When several people (or several Claude sessions) change the same engine tree:

- Say which files you are about to edit before you edit them, and don't rebuild while someone else is mid-edit.
- Make targeted edits. Never rewrite a whole file from an older copy, because that silently drops other people's work.
- After someone else regenerates the patch, check your feature is still in it (search the patch for your operation
  name).
- Copy the built `darkcloud.exe` and the changed mods to wherever the game is actually played from.
