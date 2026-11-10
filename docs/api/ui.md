# Mod Manager, HUD, screens, input and camera

Part of the [MoonFactory API reference](../API.md). What a mod can show and read: notices, Mod Manager actions and
pages, HUD layers and bars, the full-screen panels, input actions and the camera.

Every operation named here is listed with its permission and per-game support in the [operation index](OPERATIONS.md).

**In this chapter**

- [Notices (`ui.notify`)](#notices-uinotify)
- [Mod Manager actions (`ui.register`)](#mod-manager-actions-uiregister)
- [Mod Manager navigation (`ui.navigate`)](#mod-manager-navigation-uinavigate)
- [Character sheet: the Journal's Character page (Chronicle)](#character-sheet-the-journals-character-page-chronicle)
- [Input actions (`input.*`)](#input-actions-input)
- [Dungeon and town camera (`render.camera_*`)](#dungeon-and-town-camera-rendercamera_)
- [Diagnostic overlay (`debug.overlay_register`)](#diagnostic-overlay-debugoverlay_register)
- [HUD text layers, icons and the floor label (`render.layer_*`)](#hud-text-layers-icons-and-the-floor-label-renderlayer_)
- [HUD bars and target bars (`render.bar_*`)](#hud-bars-and-target-bars-renderbar_)
- [Run screens: choice panel, run menu, boss card (Chronicle)](#run-screens-choice-panel-run-menu-boss-card-chronicle)
- [Map screen, kept maps and waypoints (`ui.map_open`, Chronicle)](#map-screen-kept-maps-and-waypoints-uimap_open-chronicle)
- [Node sky in play (`ui.sky_open`, Chronicle)](#node-sky-in-play-uisky_open-chronicle)

## Notices (`ui.notify`)

```lua
local notice = assert(game.ui.notify({message = "New content is ready", duration_frames = 240}))
```

The notice is queued for the manager's status line and stays there for the requested number of game frames (1-3600,
default 240). Messages are limited to 200 bytes. Over gameplay, notices queue and pop up one at a time, each for its
duration (180 frames at least), counting down only while it is on screen. In a Chronicle dungeon each pops up in the
game's own message window at the bottom right, wrapped to three lines (a longer one ends in "..."), and waits while the
game's own message has the window. Elsewhere it is an overlay line.

An optional `icon` (Chronicle) draws in the window beside the text: `"freeze"`, `"stamina"`, `"poison"`, `"curse"` or
`"goo"` for the game's status badges, or a png game path the mod registered with `resources.override`. The manager's
status line shows the notice too if the manager is open, or when the player opens it before the duration expires.
`ui.notify` requires `game.write`.

## Mod Manager actions (`ui.register`)

```lua
assert(game.ui.register({
  id = "rescan",
  label = "Rescan area",
  description = "Refresh this mod's nearby markers"
}))

moonmod.on("ui.action", function(action)
  if action.id == "rescan" then
    -- Run mod-owned behavior here.
    assert(game.ui.remove({id = action.id})) -- Optional: remove a one-shot action.
  end
end)
```

Actions appear in the selected mod's **Actions** tab in the MoonFactory manager. Confirm or click an action to deliver
`ui.action` to that mod only. The event contains its local `id`, qualified id, label, and description. IDs accept 1-64
ASCII letters, digits, `.`, `_`, or `-`; labels are limited to 48 bytes and descriptions to 120 bytes without control
characters. A mod may register 12 actions, with a 256-action manager limit.

Both operations require `content.register`; an action can only be removed by its owner, and all owned actions are
removed when the mod unloads. These are manager actions rather than arbitrary custom pages, widgets, or draw callbacks;
those need further UI API and renderer work.

## Mod Manager navigation (`ui.navigate`)

```lua
local opened, err = game.ui.navigate({mod_id = "moonmod.adventurer", tab = "skills"})
if not opened then game.ui.notify({message = err.message}) end
```

`mod_id` must identify a valid, enabled, currently loaded package. `tab` must be one of `settings`, `actions`, `quests`,
`skills`, or `journal`, and that tab must be available for the destination. Navigation opens the existing Mod Manager if
needed, selects the package and tab, and places focus in that view. This requires `content.register`; it does not add
custom screens or bypass package enablement.

## Character sheet: the Journal's Character page (Chronicle)

```lua
assert(game.ui.sheet_set({
  title = "TOAN",                                   -- the banner: "JOURNAL: TOAN"
  lines = {"Level 12   XP 340 / 812", "Skill points: 3"},
  progress = 340 / 812, progress_label = "XP 340 / 812",
  hint = "Cross trains the selected skill.",
  trees = {"swordsman", "survivor", "explorer"}  -- the page shows the trees in this order
}))
assert(game.ui.sheet_open())   -- during play: opens the menu on the page
assert(game.ui.sheet_clear())
```

A mod with a skill tree (`skills.register`) can give the player a native page for it: **Journal > Character** in the
battle menu, drawn with the port's UI framework like the Chest Tracker. The player reaches it from the ring: **Journal >
Mod Manager > Triangle > Character** (Triangle in the Mod Manager opens the native Journal list, where Character is the
sixth category), or with a mod hotkey that calls `ui.sheet_open`. `title` is required (1-32 bytes) and `trees` names at
most 32 trees. The left pane shows the sheet's `lines` (up to six, 48 bytes each), its `hint` (80 bytes, gold) and a
progress bar when `progress` (0 to 1) is given, labelled `progress_label` (32 bytes); the right pane lists the mod's
skill nodes one tree at a time, the trees in the order `trees` names them (local tree ids; unnamed trees follow)
(Left/Right or L1/R1 change tree, Up/Down select, Circle goes back, the counter shows rank/max, a node whose
prerequisites are unmet is dimmed and its description names the first missing one). Cross on a node delivers
`skills.train_requested` with the node's qualified id to the owning mod, exactly as the Mod Manager's Skills tab does,
and the mod's next `ui.notify` message is shown on the page. The page lists only while a loaded mod has set a sheet; the
last sheet set wins when several mods have one. `ui.sheet_open` asks for the page from any mod during play and fails
when no sheet is set. In a dungeon the menu opens on the page as soon as no action is running (the same point where
Triangle would open it). In town the request is not acted on yet (the town menu has no hook for it), so use the ring
path above. `ui.sheet_clear` takes the mod's sheet back; unloading the mod does too. All three require `game.write`.
Chronicle Two has no Journal page yet, so these calls are unsupported there.

The bundled **MoonMod Hub** binds this: **K** on the keyboard, or **L1+R1+R3** held together on a gamepad, calls
`ui.sheet_open` (the page of `moonmod.rpg` or whichever mod set the last sheet). On an engine without the page, or
when no sheet is set, it falls back to `ui.navigate` to the `moonmod.rpg` Skills tab, then its Actions tab, and
shows a notice if neither opens. **J** opens the Dungeon+ journal tab.

## Input actions (`input.*`)

```lua
local action = assert(game.input.bind({id = "open_map", keys = {"M", "Gamepad:back"}}))
if assert(game.input.state({id = "open_map"})).down then
  -- Hold behavior
end
if assert(game.input.consume({id = "open_map"})).pressed then
  -- One-shot press edge; another consume call returns false until the next press
end
assert(game.input.unbind({id = "open_map"}).removed)
```

Action IDs and non-default context IDs are automatically qualified with the registering mod's ID, so mods cannot inspect
or remove another mod's action or context frame. `keys` accepts 1-8 SDL keyboard names, `Mouse1` through `Mouse5`, or
`Gamepad:<button>` names; Escape is reserved. Bind/unbind/consume and context push/pop require `game.write`, while state
and context queries require `game.read`. `input.bind` accepts an optional local `context`; it defaults to the reserved
`default` context.

`input.context_push({id})` makes that mod-owned context the active top-priority context and returns a token.
`input.context_pop({token})` removes only a frame owned by the caller; a covered frame may be removed by its owner
without disturbing the newer frame. `input.context_get()` returns the active context and the ordered stack. Only actions
bound to the active context report `down` or a consumable `pressed` edge; inactive reads return false and discard queued
press edges so they cannot fire after a later context switch. The stack is capped at 64 frames total and 16 per mod, and
all frames/actions are removed when their owner unloads. Context priority is global across mods: while a mod-owned
context is on top, mod actions assigned to other contexts are inactive. The stack does not suppress the game's native
controls.

`game.input.wheel_mode_set({mode = 0|1})` is Chronicle-only and requires `game.write`. Mode `0` routes each whole wheel
notch to Left/Right during live dungeon play; mode `1` routes it to Up/Down for menus and non-dungeon contexts.
Fractional high-resolution wheel movement is accumulated until a full notch is available. A native mouse-pointer menu
keeps its own wheel input. When no mod owns a wheel mode, Chronicle restores the existing camera-zoom routing. Requests
are owner-scoped and removed on unload; an empty object clears the caller's request.

`game.input.axis({axis = "left_x"|"left_y"|"right_x"|"right_y"|"left_trigger"|"right_trigger", pad = 0|1})` reads a
processed gamepad axis. `pad` defaults to 0. It returns `{axis, pad, connected, value}`, where stick `value` spans −1 to
1, trigger `value` spans 0 to 1, and `connected` reports whether that pad has a physical gamepad attached. Pad 0 may
still report keyboard-mapped stick input when `connected` is false. Values reflect the host's game-facing input mapping
and configured processing, rather than raw SDL samples. X is negative left and positive right; Y follows SDL's
convention, with negative up and positive down. Triggers also remain available as digital `Gamepad:L2` and `Gamepad:R2`
bindings. The query requires `game.read`.

## Dungeon and town camera (`render.camera_*`)

```lua
local camera = assert(game.render.camera_get())
print(camera.scene, camera.eye.x, camera.target.x, camera.heading)
local orbit = assert(game.render.camera_set({distance = 120, height = 15, angle = 2.25}))
```

`render.camera_get()` takes no arguments and reads the currently active dungeon camera in both ports. It returns the
camera `eye` and `target` coordinates, plus heading, pitch, and roll in the game's native angle units. It fails outside
an active dungeon or if the native camera pose is invalid.

`render.camera_set()` accepts any non-empty subset of `distance`, `height`, and `angle`, and returns the resulting
`distance`, `height` and `angle` with the values they replaced under `previous`, so a caller can put the camera back. On
Chronicle the native follow camera keeps its own reach: it eases a distance past 80 back to 80, and a height down toward 5. Distance must be 8–300 native units, height −80–150 units, and angle −1000–1000 radians; the angle is normalized
before the native camera receives it. The game eases toward the requested orbit angle in follow mode.

For Chronicle Two's player-controlled camera, distance and height must also fit the active native camera's own limits,
and its normal collision correction remains in control. The call requires a supported dungeon orbit camera: Chronicle
must be in follow mode, while Chronicle Two supports its native follow and player-controlled camera modes. Native scene
or camera transitions can later replace these values. Bounded HUD text layers are supported on both games; arbitrary
draw callbacks and world-space layers remain unsupported.

Chronicle also supports `render.town_camera_set({enabled = true, height = 90, back = 22})` for a legacy-style overhead
town view. Height is bounded to 40–500 and the forward/back offset to −200–200 native units. Requests are owned by the
calling package and removed when it unloads. The native adapter applies the pose only in the main town walking loop with
a valid player and the standard main camera; menus, events, dungeons, and camera transitions stay under native control.
The `moonmod.expanded-town` package exposes the legacy O and L1+L3 toggles, offsets in Settings, and a Toggle action in
the Mod Manager. ChronicleTwo reports this operation unsupported.

Chronicle's `render.first_person_toggle()` queues the native dungeon camera transition while normal dungeon play or the
first-person view is active. The game loop performs the transition through its existing setup and cleanup path; the
request is rejected in menus and other states.

## Diagnostic overlay (`debug.overlay_register`)

```lua
assert(game.debug.overlay_register({id = "status", text = "NEW DUNGEON READY"}))
```

`debug.overlay_register` registers or updates a single-line diagnostic shown in the game's top-left overlay on both
ports. IDs are scoped to the calling mod, so a mod may only replace its own entry. Text must contain 1–48 characters
from the overlay font's supported ASCII letters, digits, spaces, and punctuation. At most four mod entries are retained
at once, and the combined display is limited to 64 characters. Unloading the owner removes its entries. The call
requires `debug.inspect`; it does not draw arbitrary UI or provide per-frame callbacks.

## HUD text layers, icons and the floor label (`render.layer_*`)

```lua
local layer = assert(game.render.layer_register({id = "status", text = "HP 24/30"}))
assert(game.render.layer_register({id = "status", text = "HP 25/30"})) -- update
assert(game.render.layer_remove({id = "status"}))
```

`render.hud_icon_set({id, icon = "freeze"|"stamina"|"poison"|"curse"|"goo"} or {id, image = game_path}, blink?)` shows
an icon in a row left of the dungeon's key and floor plate: one of the game's status badges at half size, or a 32x32 png
the mod registered with `resources.override` (drawn 22x22). `blink = true` pulses it. At most six icons;
`render.hud_icon_remove({id})` takes one away.

`render.floor_label_set({text, number?})` puts up to six characters on the floor plate in place of its number, lettered
like it, and `number` (1-99) replaces the floor number on the card shown on arriving, in the card's own digits; one mod
at a time, and `render.floor_label_clear()` gives both back. Unloading a mod takes its icons and label away.

`render.layer_register` registers or updates one owner-scoped text layer in the native top-left HUD pass. In a dungeon,
Chronicle draws the layers in its own HUD, in the game's lettering, under the life, weapon and water block and any
`render.bar_register` bars, and `ui.notify` notices below them in the game's translucent help window. Elsewhere they are
overlay lines starting 16% down the screen (the FPS badge stays above them), with notices below. `render.layer_remove`
removes a layer owned by the calling mod. IDs cannot collide with diagnostic-overlay IDs; both APIs share a four-entry
capacity and the 64-character combined text limit. Text is restricted to the overlay font's supported ASCII set and is
drawn by the native presenter on both games.

The call requires `content.register`; owner unload removes all layers. This renderer contract is text-only and
screen-space; it does not expose arbitrary Lua draw callbacks, shapes, textures, or world-space rendering.

## HUD bars and target bars (`render.bar_*`)

Progress bars a mod draws on the HUD, and Chronicle's wider bar and meter for the locked target:

- `game.render.bar_register({id = "boss_hp", label = "Boss", current = 150, max = 200})`: Registers or updates an
  owner-scoped HUD progress bar overlay. It accepts only these fields: `label` is 1-24 overlay characters, `max` is
  positive, `current` is in `[0, max]`, and an optional boolean `boss`. A boss bar is drawn wide along the bottom of the
  screen in a dark red, its label over it, instead of in the top-left HUD. Bars share the limit of four with diagnostic
  overlays and HUD text layers.
- `game.render.bar_remove({id = "boss_hp"})`: Removes an owned HUD progress bar overlay.
- `game.render.target_bar_set({on = true})` (Chronicle only): Draws the locked target's HP as a bar half again as wide
  as the game's thin gauge under its name, framed, with a pale trail behind the red that holds what the last blows took
  for half a second and then drains away. `{on = false}` gives the game's gauge back. The game's setting that hides the
  target gauge hides this bar too.
- `game.render.target_meter_set({entity, fill = 0..1, color = {r, g, b}?, seconds?})` (Chronicle only): A thin meter
  under that monster's target bar, shown while it is the locked target and the bar is on (a poise or stagger meter).
  `color` defaults to gold; a full meter flashes white. It goes after `seconds` (0 to 600) without another set, or stays
  with 0, the default. `{entity}` alone takes it away. A monster that has gone fails with "that monster is gone", and
  the meter goes with the monster when another takes its slot.

## Run screens: choice panel, run menu, boss card (Chronicle)

During dungeon play a mod can put up three screens of its own, each drawn by the engine in the game's own stone
plates and lettering, driven by the pad or the mouse, and spread across a wide window:

- `ui.choice_open({id, title, subtitle?, cancel?, cursor?, options = {{title, subtitle?, lines?}, ...}})` pauses the
  dungeon (as the game's pause does) on 1-6 option cards side by side. A line is a string or `{text, tone}` with tone
  `good`, `bad`, `dim` or `gold`. Left/right (or L1/R1) move, Cross takes, Circle backs out when `cancel` is set; the
  mouse picks the card under it. The owner gets `ui.choice_made` `{id, index}` (index from 1) or `{id, cancelled =
  true}`. One panel at a time; it waits for play to be free (not mid-chest) before it shows. Notices hold back while it
  is up. `ui.choice_close()` takes it away. With `town = true` it opens in a town too while the party walks free: there
  the town goes on around it and only the party's controls wait. Without it a panel opens only in dungeon play.
- `ui.run_menu_set({title, tabs = {{id, title, lines?, rows?}, ...}})` gives the mod a run menu: while it has one,
  Start in a dungeon opens it in place of the bare pause. Up to 6 tabs (L1/R1) of up to 64 rows (`{id, label, value?,
  detail?, tone?, enabled?}`); a side pane shows the tab's lines and the chosen row's detail. Cross on an enabled row
  sends `ui.run_menu_action` `{tab, row}`; set the menu again to show the result (the cursor stays on the same tab and
  row ids). `ui.run_menu_open({tab?})` opens it from the mod (when play is next free), `ui.run_menu_close()` and
  `ui.run_menu_clear()` close and remove it; `ui.run_menu_shown` `{open, tab}` reports it opening and closing. Leave
  out an empty `rows` or `lines` (or send none) rather than an empty table.
- `ui.boss_card({name, kicker?, epithet?, frames = 30-600})` is a boss's entrance: letterbox bars, the kicker in red,
  the name large in gold and the epithet under it, the scene held still while it shows.

## Map screen, kept maps and waypoints (`ui.map_open`, Chronicle)

```lua
local snap = game.dungeons.map_snapshot()            -- {seed, width = 96, cells, seen}: what the player has seen
game.dungeons.set_seen({seed = snap.seed, cells = snap.cells})   -- next visit (same seed): seen again
game.dungeons.set_waypoint({x = 30, y = 21})         -- the red flag on the mini map; {} takes it away
game.ui.map_open({id = "map", title = "Divine Beast Cave", subtitle = "Floors 1-7",
  marks = {{x = 30, y = 20, kind = "shrine_lit", label = "Floor 3", pick = true}},
  waypoints = true})                                 -- the floor the player is on
game.ui.map_open({id = "map", title = "Divine Beast Cave", cells = snap.cells, hint = "Travel",
  marks = marks, pages = true})                      -- a kept map, in a town too
```

- `ui.map_open({id, title, subtitle?, cells?, marks?, cursor?, waypoints?, hint?, pages?})` opens the map screen. In a
  dungeon it pauses play as the choice panel does; in a town (while walking) it holds the town's controls. Without
  `cells` it is the floor the player is on (dungeon only), showing the cells they have seen (all of them with the
  floor's map item), the player, and the marks; with `cells` from `dungeons.map_snapshot` it is that kept map,
  anywhere. Rooms are blocks, roads lines between the cells they join. A mark is `{x, y, kind?, label?, pick?}` with
  kind `shrine` (not lit), `shrine_lit`, `waypoint`, `gate`, `stair` or `mark`; up to 64. A `shrine` or `gate` mark
  stays hidden until its cell has been seen. The cursor starts at `cursor`, else on the player, else the middle of the
  map; the pad or left stick moves it, L1/R1 step between `pick` marks, Cross on one sends `ui.map_choice` `{id, x, y,
  mark}` (mark numbered from 1, as listed) and closes, Triangle (with `waypoints`) puts or takes away the one waypoint
  under the cursor (`ui.map_waypoint` `{id, x, y, set}`; on the live map the mini map's flag moves at once), L2/R2
  (with `pages`) send `ui.map_page` `{id, way = -1 | 1}`, and Circle, Select or Start close it (`ui.map_closed`).
  Opening again while the mod's own map is up replaces it in place, which is how a page turns. One mod's map at a
  time; `ui.map_close()` takes it away, and unloading the mod does too.
- `dungeons.map_snapshot()` returns the floor the player is on as far as they have seen it: `{seed, width, cells,
  seen}`, `cells` a short text (each cell a letter, runs counted) to keep in a mod's save. Unseen cells are left out.
- `dungeons.set_seen({seed, cells})` counts a kept map's cells as seen again on the floor the player is on, when that
  floor was built from `seed` (`{applied = false}` otherwise). Call it from `game.dungeon.generated`.
- `dungeons.set_waypoint({x, y})` puts the waypoint flag on the mini map for the floor the player is on (held at the
  mini map's edge while it lies outside the part shown); `{}` takes it away. A floor built from another seed doesn't
  show it.
- On a map too big for the corner (a region of several floors) the mini map shows the part around the player, at a
  readable size, scrolling as they walk, in a framed box.

## Node sky in play (`ui.sky_open`, Chronicle)

```lua
game.ui.sky_open({id = "sky", title = "VIGIL SKY", hint = "{dpad} Move  {cross} Level up  {circle} Back",
  sky = {groups = groups, nodes = nodes, top = {"Level 3", "Gilda 1200", "Embers 2"}}})
moonmod.on("ui.sky_selected", function(e)        -- {id, entry, action = "buy" | "toggle" | "rank_down" | "rank_up"}
  if e.action == "buy" then buy(e.entry) game.ui.sky_open({id = "sky", title = "VIGIL SKY", sky = page()}) end
end)
```

- `ui.sky_open({id, title, hint?, sky})` (`game.write`) opens a node sky over the dungeon and pauses it, as the map
  screen does. `sky` is what `title.mode_set` takes as its `sky` (groups, nodes, links, states, Keystones, the top
  lines), read and drawn the same way; `id` is 1-64 bytes, `title` 1-32 and `hint` up to 160. The pad or left stick
  moves between nodes, L2/R2 jump between constellations and Triangle shows the whole sky. Cross sends
  `ui.sky_selected` with action `buy`, Square `toggle`, L1 `rank_down` and R1 `rank_up`. Circle, Select or Start close
  it (`ui.sky_closed` `{id}`). The engine changes nothing itself: the mod answers by opening the page again with the
  new states, which keeps the cursor on the node it was on. It opens only during dungeon play, and one mod's page at a
  time; `ui.sky_close()` takes it away, and unloading the mod does too.
