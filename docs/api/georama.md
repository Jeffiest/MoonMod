# Georama

Part of the [MoonFactory API reference](../API.md). Reading a town's Georama, completing requests, registering piece
variants, placing and removing pieces, and Chronicle's Atla.

Every operation named here is listed with its permission and per-game support in the [operation index](OPERATIONS.md).

**In this chapter**

- [Georama state, requests and placement (`georama.*`)](#georama-state-requests-and-placement-georama)
- [Variants with their own model (Chronicle)](#variants-with-their-own-model-chronicle)
- [Variants with their own footprint (Chronicle)](#variants-with-their-own-footprint-chronicle)
- [Atla and town satisfaction (Chronicle)](#atla-and-town-satisfaction-chronicle)
- [Georama events](#georama-events)

## Georama state, requests and placement (`georama.*`)

```lua
-- Omit town_id to query the active Georama town, or pass 0 through 5.
local town = assert(game.georama.get())
for _, part in ipairs(town.placed_parts) do
  print(part.id, part.position.x, part.position.y, part.position.z)
end
for _, grid in ipairs(town.river_grids) do
  for x, row in ipairs(grid.cells) do
    for z, has_river in ipairs(row) do
      if has_river then print("river", grid.index, x - 1, z - 1) end
    end
  end
end

-- Chronicle Two only; requires an active town-edit scene and an existing grid.
assert(game.georama.river_set({grid_index = 0, x = 0, z = 1, has_river = true}))

local request = assert(game.georama.request_set({town_id = 2, request_id = 1, completed = true}))
print(request.previous, request.completed, request.changed)

-- Chronicle only: register a data-only variant in an appended editor slot.
local chronicle_variant = assert(game.georama.register({
  id = "garden-post", name = "Garden Post", template_part_id = 4,
  town_id = 2, stock = 1
}))
print(chronicle_variant.id, chronicle_variant.native_part_id, chronicle_variant.materialized)

-- Chronicle Two only: choose a loaded native template and add a build-menu variant.
local templates = assert(game.georama.get({town_id = 2})).native_piece_templates
local piece = assert(game.georama.register({
  id = "moonstone-pillar", name = "Moonstone Pillar",
  template_part_id = assert(templates[1]).template_part_id
}))
print(piece.id, piece.status)

-- Chronicle Two only: requires built stock and an active town-edit scene.
local placed = assert(game.georama.place({
  id = piece.id, position = {x = 12, y = 0, z = 8}, rotation_steps = 0
}))
print(placed.placement_id, placed.remaining_built)

-- Chronicle Two only: remove a current placement from the active town edit scene.
local removed = assert(game.georama.remove({placement_id = placed.placement_id}))
print(removed.removed, #removed.returned_stock)

-- Chronicle Two only: this may affect multiple requests that share the condition.
local condition = assert(game.georama.condition_set({town_id = 2, condition_id = 5, met = true}))
print(condition.previous, condition.met, condition.changed)

-- Chronicle Two only: reveal an existing request without completing it.
local knowledge = assert(game.georama.request_known_set({town_id = 2, request_id = 1, known = true}))
print(knowledge.previous, knowledge.known, knowledge.changed)

-- Chronicle only: toggle a defined optional element in the active town editor.
local element = assert(game.georama.element_set({
  town_id = 2, plot_id = 4, element_id = 1, enabled = true
}))
print(element.previous, element.enabled, element.changed)

-- Chronicle only: place and remove the registered variant by stable ID.
local mod_placed = assert(game.georama.place({
  town_id = 2, part_id = chronicle_variant.id,
  position = {x = 12, y = 0, z = 8}, rotation_quarter_turns = 0
}))
assert(game.georama.remove({placement_id = mod_placed.placement_id}))

-- Chronicle only: place an existing piece after it has native built stock.
local placed = assert(game.georama.place({
  town_id = 2, part_id = 4, position = {x = 12, y = 0, z = 8}, rotation_quarter_turns = 0
}))
print(placed.placement_id, placed.remaining_built)
assert(game.georama.remove({placement_id = placed.placement_id}))
```

### Chronicle

Chronicle reads the active save's six native town records. The result includes the selected `town_id`, request
completion count, all 24 plot records (completion flags, obtained/placed/stock values, and six attachment-element
states), plus placed parts with native numeric part IDs or stable namespaced mod piece IDs, quarter-turn rotation,
position, and a unique `placement_id` suitable for removal.

While that town's editor is active, the result also includes `placement_areas` (world-space grid origins and dimensions)
and `native_pieces` (loaded native part ids, footprint sizes, and available built stock) plus active-town `mod_pieces`
(registered stable IDs, assigned slots, materialization state, and available stock). Passing `{town_id = 0..5}` reads a
town even when it is not active; omitting it while in a dungeon fails with `failed`.

`georama.request_set` writes the completion bit for an already defined request in that town and returns its previous and
resulting states. `georama.element_set({town_id, plot_id, element_id, enabled})` toggles an optional element defined for
a native plot. It requires that town's active editor, rejects absent elements and unsatisfied native element
dependencies, updates the live editor state and save data, and emits deferred `game.georama.element_changed` when the
value changes.

`georama.place({town_id, part_id, position, rotation_quarter_turns})` accepts an existing native piece by numeric part
ID or a registered data-only variant by stable ID and requires built stock; native fit, collision, and placement checks
still decide whether it can be placed. Rotation is 0 through 3 quarter turns. `georama.remove({placement_id})` removes a
placement identified by the current `georama.get()` result, subject to the game's fixed-piece and dependency rules.
Successful place/remove calls save the active editor state and emit deferred piece events.

Chronicle `georama.register({id, name, template_part_id, town_id?, stock?})` creates up to 32 data-only variants in
persistent native definition slots 24–55, without changing the retail save record layout. Each variant inherits a loaded
native solid template's model, collision, footprint, and native placement behavior. A variant can declare its own model
and footprint (the two sections below); other custom geometry is unsupported. Registration materializes for the selected
town, or all towns when `town_id` is omitted; `stock` initializes built stock from 1 through 999. The native menu can
enumerate the appended definitions, but menu text and icons still come from the template; the mod-supplied name appears
in API metadata.

Unregister is refused while a saved layout or active placement refers to the variant, and the stable slot remains
reserved for that stable ID across launches. The retail headless probe registers a variant, places it through the native
editor path, verifies saved-layout readback, removes it, and confirms it is gone. It does not verify rendering after
process reload or compatibility with player saves.

### Chronicle Two

ChronicleTwo's `georama.get()` reads the active saved town while the game is in the town-edit loop; `{town_id = 0..4}`
selects any saved town from other scenes. It returns the native save/culture counters, placed part IDs with stable
save-slot identifiers, placement state, 24-step rotation, integer position, paint colors and house links, saved house
occupants, the native known-request/met-condition flags, native `native_piece_templates` discovered for towns whose map
definitions have loaded, and registered mod piece variants with their per-town native IDs/status.

`known_requests` means the game has exposed those requests to the player; it does not claim they are complete.
`georama.request_set({town_id, request_id, completed})` requires a loaded native request definition and changes its
prerequisite condition bytes through the native request setter; the result reports previous/resulting completion,
whether it changed, and the current town progress percentage. Conditions can be shared by requests, and the operation
does not run request reward scripts.

`georama.request_known_set({town_id, request_id, known})` changes one of the town's 16 native request-knowledge bytes
and returns its previous/resulting value and whether it changed. `georama.condition_set({town_id, condition_id, met})`
updates one of the town's 64 native analysis-condition bytes using the game's bounded debug setter. The condition can be
shared by multiple requests, so the call does not mean a single request was completed.

`georama.register({id, name, template_part_id})` copies a native piece definition into each loaded town's build table
under a namespaced mod id, reusing its native model, collision, rules, and materials. The original Georama menu can then
build the variant. `georama.place` is available only in the live town-edit scene, accepts registered solid template
variants with available built stock, and uses the game's native collision and placement checks before updating saved
layout state.

`georama.remove` also requires the active edit scene and a current placement id from that town's saved layout; stale
ids, fixed pieces, and river-grid pieces fail without changing state. The native removal routine handles dependency
cascades, stock returns where the definition allows them, and housed villagers; the adapter updates the save, culture
score, and analysis state. Neither operation provides authored geometry/assets or completes request rewards.

ChronicleTwo supports `georama.get` for its five saved reconstruction towns, including saved river-grid dimensions,
positions, and per-cell river state, `georama.request_set` for completion of an already defined native request,
`georama.condition_set` for a saved town's existing analysis condition, and `georama.request_known_set` for the native
request-knowledge byte. During an active town edit scene, ChronicleTwo also returns bounded `placement_anchors` from
placed parts with floor collision data; each anchor includes its native part id/name, position, surface height, floor
area, and local floor bounds for placement discovery.

This field is empty outside a matching active town editor. River-grid cells are reported as `cells[x][z]` booleans
decoded from the saved town data. `georama.river_set({grid_index, x, z, has_river})` sets or clears an existing grid
cell in an active town-edit scene. Grid and cell indices are zero-based; the call uses the native neighbor-shaping
routines, persists the town, recomputes its Georama analysis, and emits deferred `game.georama.river_changed` only when
a cell changes. The condition setter updates the native condition byte and can affect every request that depends on it;
request knowledge is separate and does not mark a request complete.

`georama.register({id, name, template_part_id})` adds a data-only piece variant to the native build definitions. The new
entry inherits its template's native model, collision, placement rules, and material cost, and is available through the
game's Georama build menu; per-town registration status appears in `georama.get().mod_pieces`.

ChronicleTwo's `georama.place({id, position, rotation_steps})` places a registered solid piece in an active town-edit
scene through the game's native collision, placement, stock, and count checks. The piece must already have built stock,
so a mod can provide its definition while the game's normal menu handles material requirements.
`georama.remove({placement_id})` removes a saved placement from the active town-edit scene using its current
`georama.get()` id. The game decides whether a fixed piece may be removed, cascades native dependent removals, returns
eligible build stock, releases housed villagers, and saves the updated town. Successful placement and removal emit
deferred `game.georama.piece_placed` and `game.georama.piece_removed` events.

Creating new river grids, authored geometry/assets, request rewards, and authored towns remain unsupported. The catalog
continues to report unsupported authored locations, wholly new dungeons, native skill bonuses, and fighting styles. Both
games support model-embedded motion indices through their animation APIs; standalone animation assets remain
unsupported. ChronicleTwo's current dungeon support adds a floor to an existing native dungeon; it does not yet register
a wholly new dungeon.

## Variants with their own model (Chronicle)

`game.georama.register` accepts an optional `model = {scene = <scene file>, part = <part archive name>}`. `scene` is
either a retail `gedit/<town>/scene.scn` or a mod's own `gedit/mod/<name>.scn`. A `gedit/mod/` scene is a new path, up
to 8 MiB, with a name of 1-15 `[a-z0-9_]` characters, and the mod must own its override before registering. `part` is the
name of a part archive inside that scene (up to 31 characters), for example `e01h05`. When the variant is set up in the
town editor, its LOD0-3, shadow, collision, shade, ripple and camera models come from that archive, and its bounds and
placement preview are recomputed. Footprint, function points, stock behaviour, menu name and icon still come from
`template_part_id`. If the scene or part cannot be loaded, the variant keeps the template's model and the game logs it.
Up to 8 distinct scene files stay loaded per session. The model's textures must be in the town's loaded texture pack.

```lua
assert(game.resources.override({path = "resources/gedit/mod/moonhouse.scn", game_path = "gedit/mod/moonhouse.scn"}))
local house = assert(game.georama.register({
  id = "moon-house", name = "Moon House", template_part_id = 0, town_id = 0, stock = 3,
  model = {scene = "gedit/mod/moonhouse.scn", part = "e01h05"},
}))
```

## Variants with their own footprint (Chronicle)

```lua
game.georama.register({id = "long_fence", name = "Long Fence", template_part_id = 0, town_id = 0, stock = 5,
  footprint = {width = 4, height = 1}})                          -- every cell filled
game.georama.register({id = "corner", name = "Corner", template_part_id = 0, town_id = 0,
  footprint = {width = 2, height = 3, cells = {5, 0, 5, 0, 5, 5}}}) -- row by row, 0 = empty
```

`width`/`height` are 1-32 cells. `cells` holds width x height values 0-255 as the part definition file has them
(0 empty, other values as the template uses them); left out, every cell takes the template's most used non-empty
value. The model and collision still come from the template (or `model = {scene, part}`). `georama.get().mod_pieces`
reports `width_cells`/`height_cells`.

## Atla and town satisfaction (Chronicle)

Chronicle's Atla spheres and a per-town view of how much of each town is rebuilt:

- `game.georama.atla_list()` requires an active dungeon floor and returns the open Atla spheres with their live slot,
  native Atla registry index and id, registry floor/refcount, world position, and whether the contents are a Georama
  part or chip plus its saved obtained/placed/stock state.
- `game.georama.atla_spawn({id, name, position?})` (`game.write`) puts a mod's own Atla sphere on the active dungeon
  floor: at `position` (`{x, y?, z}`), or a free spot as the floor's own spheres are put. Toan opens it as he does
  theirs, and the pickup says `"<name>" acquired`. It holds nothing of the game's (no Georama part or chip, no save
  record); `game.georama.atla_collected` tells the mods `{id, owner, name}`, and the mod keeps what it means (a story
  flag, say). It lasts for that floor; put it again on a later visit while the mod still wants it found.

  A floor holds 80 spheres (the game puts 8 at most; a map of eight floors' zones, 64), and one picked up leaves its
  place free; up to 16 mod spheres can be registered. Each `atla_list` entry has `floor_id`, the floor the sphere
  belongs to (a region's zone's floor). `atla_list` shows mod spheres with `contents = {kind = "mod", id, owner, name}`.
- `game.georama.atla_collect({slot = 0..15})` requires an active dungeon floor and Toan as the controlled character. It
  uses the game's native Atla save routine (`getAtraToSaveData`), marks the live ball and matching dungeon event closed,
  and releases the part or chip into the same saved state as a native pickup. It does not transfer ownership of a
  mod-authored asset.
- `game.georama.satisfaction_get({town_id = optional 0..4})` returns each requested Chronicle town with saved request
  completion, a rounded `satisfaction_percent` derived from completed native requests, and per-plot `obtained`,
  `placed_count`, `stock`, and element flags. The percentage is a framework view over native request state; retail has
  no separate satisfaction statistic.

## Georama events

Successful, changed native writes queue `game.georama.request_changed` on Chronicle and `game.georama.request_changed`,
`game.georama.condition_changed`, and `game.georama.request_known_changed` on Chronicle Two. Piece placements and
removals queue `game.georama.piece_placed` and `game.georama.piece_removed` on both ports. Removal events also include
cascade counts, returned build stock, and released villagers on Chronicle Two. Payloads include the town and
request/condition/part identifiers, previous and resulting state where applicable, `changed`, `source_mod`, and frame.
Repeating a setter with the same value is idempotent and does not enqueue another event. Quest objectives may subscribe
to these events with an exact `match` filter.
