# MoonFactory Code Review & Synchronization Ledger

This document tracks the code review findings, architectural parity across the three `TheMoonPeople` repositories (`MoonFactory`, `Chronicle`, and `ChronicleTwo`), and the chronological history of all fixes applied.

## Architectural Scope & Repository Topology

- **Canonical Runtime**: `MoonFactory/` (`include/moonmod/`, `src/`, `tools/`, `docs/`, `verify-headless.ps1`)
- **Dark Cloud (`Chronicle`) Port Copy**: `Chronicle/port/include/moonmod/`, `Chronicle/port/src/moonmod/`
- **Dark Chronicle / Dark Cloud 2 (`ChronicleTwo`) Port Copy**: `ChronicleTwo/port/include/moonmod/`, `ChronicleTwo/port/src/moonmod/`

---

## Findings Addressed

1. **Critical — Lua Instruction Budget Sandbox Bypass (`src/lua_runtime.cpp`)**
   - `OpenSafeLibraries` leaves `pcall` and `xpcall` enabled in the sandbox global table, while `InstructionHook` raises a catchable `luaL_error` when `budget_remaining <= kHookInterval`.
   - A script executing `while true do pcall(function() while true do end end) end` could catch the budget error repeatedly and run forever.
   - **Resolution**: Added sticky `budget_exceeded` state to `LuaMod::Impl`. Once `InstructionHook` trips, `budget_exceeded` is latched to `true`, `budget_remaining` is zeroed, and the Lua hook mask is tightened to `LUA_MASKCOUNT | LUA_MASKCALL | LUA_MASKRET` with count `1` so any outer `pcall`/`xpcall` recovery frame immediately re-traps on the next instruction or return. `ProtectedCall` also checks `budget_exceeded` after `lua_pcall` completes.

2. **High — 3-Way Source Drift Between `MoonFactory/`, `Chronicle/port/`, and `ChronicleTwo/port/`**
   - 12 of 22 files in `MoonFactory/{include/moonmod,src}` were behind the port copies and `docs/API.md` (136 vs. 139 API operations, missing Quests/Skills/Journal manager UI tabs, missing quest rewards and skill effects, missing `events.list` and `game.world.location_changed` polling).
   - 4 shared files (`src/api.cpp`, `src/runtime.cpp`, `src/native_resource_overrides.cpp`, `include/moonmod/native_resource_overrides.hpp`) had also diverged between `Chronicle` and `ChronicleTwo`.
   - **Resolution**: Merged the complete superset of `Chronicle` and `ChronicleTwo` runtime capabilities into `MoonFactory/{include/moonmod,src}`, synchronized identical copies across all three locations, and added a source-parity check to `verify-headless.ps1`.

3. **High — Incomplete Standalone Library Target (`CMakeLists.txt`)**
   - `MoonFactory/CMakeLists.txt` omitted `src/audio_api.cpp`, `src/native_plugin_contract.cpp`, `src/native_plugin_hash.cpp`, and `src/native_plugin_loader.cpp` from `add_library(moonmod ...)`.
   - **Resolution**: Added all four missing implementation files to `MoonFactory/CMakeLists.txt`.

4. **Medium — `LuaMod::Impl::Allocate` Heap Usage Underflow (`src/lua_runtime.cpp`)**
   - Per the Lua 5.4 `lua_Alloc` contract, when `pointer == nullptr`, `old_size` holds the Lua object type tag (`LUA_T*`), not a byte count. In the `new_size == 0` branch, `Allocate` subtracted `old_size` unconditionally even when `pointer == nullptr`.
   - **Resolution**: Guarded `memory.used` subtraction in the `new_size == 0` branch with `if (pointer != nullptr)`.

5. **Medium — `NativePluginInstance::Load` Lifecycle & Error Buffer Handling (`src/native_plugin_loader.cpp`)**
   - `NativePluginInstance::Load` called `plugin->unload()` even when `plugin->load()` failed or threw, and dropped error messages if `message.length >= error_buffer.size()` or if `message.data` pointed to a static string literal.
   - **Resolution**: Removed the erroneous `plugin->unload()` call on failed `load()`, gated `Unload()`'s `plugin->unload()` call on `impl_->loaded`, and bounded error extraction via `std::min<std::size_t>(message.length, error_buffer.size() - 1)`.

6. **Medium — `NativeJsonApiCallable` Missing `scripts.override` (`src/runtime.cpp`)**
   - `MoonFactory/src/runtime.cpp` omitted `scripts.override` in `NativeJsonApiCallable`.
   - **Resolution**: Added `path != "scripts.override"` to `NativeJsonApiCallable`.

7. **Low — Repeated `std::regex` Compilation (`src/manifest.cpp`, `src/lua_runtime.cpp`)**
   - Validation helpers re-compiled `std::regex` objects on every invocation.
   - **Resolution**: Promoted `std::regex` instances in `src/manifest.cpp` and `src/lua_runtime.cpp` to `static const std::regex`.

---

## Edit History

- **Edit 0 (Baseline Documentation)**: Created `docs/CODE_REVIEW_CHANGELOG.md` to record all review findings and track every subsequent edit.
- **Edit 1 (`CMakeLists.txt`)**: Added `src/audio_api.cpp`, `src/native_plugin_contract.cpp`, `src/native_plugin_hash.cpp`, and `src/native_plugin_loader.cpp` to `add_library(moonmod STATIC ...)` so the standalone `moonmod` target compiles and links all required symbols.
- **Edit 2 (Port Baseline Sync to `MoonFactory/`)**: Synced the latest port versions of `include/moonmod/{api,combat_formula,manager_ui,manifest,runtime}.hpp` and `src/{lua_runtime.hpp,lua_runtime.cpp,manager_ui.cpp}` into `MoonFactory/`.
- **Edit 3 (`include/moonmod/native_resource_overrides.hpp`, `src/native_resource_overrides.cpp`)**: Unified `Chronicle` map path aliasing (`RegisterNativeResourcePathAlias` / `FindNativeResourcePathAlias`) and `ChronicleTwo` persistent content overrides (`NativeResourceOverrideSize` / `SetNativeResourceOverridePersistent`) into a single implementation that preserves both ports' exact status/message contracts.
- **Edit 4 (`src/api.cpp`, `src/runtime.cpp`)**: Unified `kApiCatalog` (139 operations), `kEventCatalog` (36 events including `game.item_picked_up`), and `UnsupportedReason` across both games; unified `runtime.cpp` to emit both `game.georama.element_changed` and `game.georama.river_changed` and reject `scripts.override` in `NativeJsonApiCallable`.
- **Edit 5 (`src/lua_runtime.cpp`)**: Fixed `LuaMod::Impl::Allocate` so freeing a null pointer does not subtract the Lua type tag (`old_size`) from `memory.used`, and hardened `InstructionHook` + `ProtectedCall` with a sticky `budget_exceeded` flag and 1-instruction `LUA_MASKCOUNT | LUA_MASKCALL | LUA_MASKRET` trap so `pcall`/`xpcall` loops cannot bypass `lua_instructions_per_callback`.
- **Edit 6 (`src/native_plugin_loader.cpp`, `src/manifest.cpp`)**: Removed the erroneous `plugin->unload()` invocation when `plugin->load()` fails, gated `Unload()` on `impl_->loaded`, hardened `message` buffer extraction, and promoted `std::regex` objects in `manifest.cpp` to `static const`.
- **Edit 7 (3-Way Synchronization & Sandbox Regression Test)**: Synchronized all 22 canonical headers and sources from `MoonFactory/{include/moonmod,src}` to `Chronicle/port/{include,src}/moonmod` and `ChronicleTwo/port/{include,src}/moonmod`, and updated `moonmod_api_test.cpp` in both ports to exercise `while true do pcall(function() while true do end end) end` in the instruction budget test.
- **Edit 8 (`verify-headless.ps1`, `ChronicleTwo/port/src/tests/moonmod_api_test.cpp`)**: Added an automated SHA-256 source-parity gate in `verify-headless.ps1` ensuring `MoonFactory/{include/moonmod,src}` never drifts from `Chronicle/port` or `ChronicleTwo/port`, and synced the `pcall` infinite-loop regression test into `ChronicleTwo`.
- **Edit 9 (`Chronicle/port/src/tests/moonmod_api_test.cpp`, `ChronicleTwo/port/src/tests/moonmod_api_test.cpp`)**: Updated the `local core` filter table in `ExerciseApi` to include the three built-in script hook operations (`scripts.list_hooks`, `scripts.call`, `scripts.override`) that are marked core in `IsCoreApiOperation()`, preventing the non-core adapter dispatch probe loop from invoking `scripts.list_hooks` with dummy `{probe = "every-domain"}` arguments.
- **Edit 10 (Tier 1 Cross-Game Parity)**:
  - Promoted `game.item_picked_up` to `"both"` in `MoonFactory/src/api.cpp` (synced to both ports), implemented `ChronicleNativeItemPickedUp` in `Chronicle/port/src/moonmod/chronicle_adapter.cpp`, and hooked native dungeon pickups (`BtGetTreasureboxBig_Loop`, `BtGetTreasureboxSmall_Loop`, `BtGetAttach_Init`) in `Chronicle/ps2/src/btitem.cpp`.
  - Implemented `entities.set_active_limit` in `ChronicleTwo` (`ChronicleTwo/ps2/include/monster.hpp`, `ChronicleTwo/ps2/src/monster.cpp`, `ChronicleTwo/port/src/moonmod/chronicle_two_adapter.cpp`) controlling `MonsterActiveLimit` and live `CMonsterMan::priority_limit` (`1..MONSTER_ACTIVE_MAX`).
  - Implemented `dungeons.set_layout` in `ChronicleTwo` (`ChronicleTwo/ps2/include/automap.hpp`, `ChronicleTwo/ps2/src/automap.cpp`, `ChronicleTwo/ps2/src/dng_event.cpp`, `ChronicleTwo/port/src/moonmod/chronicle_two_adapter.cpp`), expanding `AUTOMAP_ROOM_MAX`/`DNG_ROOM_MAX` to `64` under `#ifdef PORT` and wiring `DngLayoutRooms`, `DngLayoutArea`, `DngLayoutRoomMin`, and `DngLayoutRoomMax` into `CAutoMapGen`.
  - Aligned `animations.*` and `game.item_picked_up` test expectations and added unit tests in `Chronicle/port/src/tests/{moonmod_api_test,moonmod_items_api_test}.cpp` and `ChronicleTwo/port/src/tests/{moonmod_api_test,moonmod_entities_api_test,moonmod_dungeon_registration_test}.cpp`; updated `MoonFactory/docs/API.md`.
- **Edit 11 (Tier 1 Build & Test Contract Alignment)**:
  - Replaced `#include "moonmod/chronicle_adapter.hpp"` in `Chronicle/ps2/src/btitem.cpp` with a direct `moonmod::ChronicleNativeItemPickedUp` forward declaration under `#ifdef PORT` so the `dc_ps2` target compiles without requiring `nlohmann_json` include directories.
  - Updated `ResetChronicleTwoContentForTests()` in `ChronicleTwo/port/src/moonmod/chronicle_two_adapter.cpp` to reset `DngLayoutRooms = 0` and `DngLayoutArea = 0`, aligned `Chronicle/port/src/tests/moonmod_items_api_test.cpp` to pass `ITEM_WEAPON_START` (`256`) for native weapon pickup verification, and aligned `ChronicleTwo/port/src/tests/{moonmod_entities_api_test,moonmod_dungeon_registration_test}.cpp` and `MoonFactory/docs/API.md` with the exact `{active = ...}` and `{}` / `"grid"` / `"room_limit"` contracts.
- **Edit 12 (Tier 2 Cross-Game API Expansion & Native Verification)**:
  - Expanded `kApiCatalog` across all 3 repos to 161 operations with 33 domains by adding 19 Tier 2 APIs:
    - Render: `render.bar_register`, `render.bar_remove`
    - Weapons: `weapons.abs_get`, `weapons.abs_add`, `weapons.attachments_get`, `weapons.attachment_insert`, `weapons.attachment_remove` (`chronicle` only), `weapons.build_up_list`, `weapons.build_up_register`, `weapons.synthesize` (`chronicle` only), `weapons.spectrumize` (`chronicle-two` only)
    - Shops: `shops.list`, `shops.get`, `shops.register_item`, `shops.remove_item`, `shops.set_price`
    - Dungeons: `dungeons.floor_rules_get`, `dungeons.floor_rules_set`, `dungeons.loot_get`, `dungeons.loot_override`
  - Added 5 native script hooks to `lua_runtime.cpp`: `native.event.run`, `native.dialogue.show`, `native.combat.before_hit`, `native.loot.roll`, `native.transition.before_enter`.
  - Added 6 deferred events: `game.weapon.abs_gained`, `game.weapon.built_up`, `game.weapon.broken`, `game.shop.purchased`, `game.chest.opened`, `game.floor.cleared`.
  - Implemented Tier 2 handlers in both `Chronicle/port/src/moonmod/chronicle_adapter.cpp` and `ChronicleTwo/port/src/moonmod/chronicle_two_adapter.cpp` using native data structures (`ATTACH_LIST`, `ATTACH_DATA`, `WEAPON_HAVE`, `WEAPON_DATA`, `DNG_CONSUMABLE`, shop inventories, floor rules/seals, and chest/loot tables).
  - Cleaned up misplaced `port/src/api.cpp`, `port/src/lua_runtime.cpp`, and restored original PS2 runtime stub `port/src/runtime.cpp` in both ports.
  - Maintained 100% 3-way canonical source parity (22 files) checked by `verify-headless.ps1`.
  - Updated `MoonFactory/docs/VERIFICATION.md` table to include the `shops` domain, and aligned test assertions in both ports for 5 script hooks and the `shops` domain.
  - Verified full headless pass: Python 14/14 passed, Chronicle native tests 78/78 passed, ChronicleTwo native tests 80/80 passed, clean-root repeatability passed for both, and retail-data startup smokes passed with exit code 0.

