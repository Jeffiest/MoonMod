# Package files, overrides, audio, text, models and animations

Part of the [MoonFactory API reference](../API.md). Reading a package's own files, replacing the game's files, playing
audio, changing game text, and binding models and motions.

Every operation named here is listed with its permission and per-game support in the [operation index](OPERATIONS.md).

**In this chapter**

- [Package resources (`resources.load`)](#package-resources-resourcesload)
- [Native file overrides (`resources.override`)](#native-file-overrides-resourcesoverride)
- [Overrides larger than retail (Chronicle)](#overrides-larger-than-retail-chronicle)
- [Override reload and notices (Chronicle)](#override-reload-and-notices-chronicle)
- [Package audio (`audio.register`, `audio.play`)](#package-audio-audioregister-audioplay)
- [Retail sound and music (`audio.se_play`, `audio.bgm_play`, `audio.music_set`,
  Chronicle)](#retail-sound-and-music-audiose_play-audiobgm_play-audiomusic_set-chronicle)
- [Game text (`text.*`, Chronicle)](#game-text-text-chronicle)
- [Mesh and texture replacements (Chronicle)](#mesh-and-texture-replacements-chronicle)
- [Monster model resolution (`models.*`)](#monster-model-resolution-models)
- [Animations (`animations.register`, `animations.play`)](#animations-animationsregister-animationsplay)
- [Playable-character motions (`animations.player_register`,
  Chronicle)](#playable-character-motions-animationsplayer_register-chronicle)
- [Monster motions (`animations.monster_register`, Chronicle)](#monster-motions-animationsmonster_register-chronicle)

## Package resources (`resources.load`)

```lua
local resource = assert(game.resources.load({path = "resources/icon.png"}))
local payload = assert(game.resources.resolve({handle = resource.handle}))
assert(payload.encoding == "base64")
-- Decode payload.data in Lua or pass it to a native extension that understands the format.
assert(game.resources.release({handle = resource.handle}).removed)
```

Paths must stay under the package's `resources/` directory. The runtime rejects absolute paths, traversal components,
symbolic links, and non-files. A mod may hold up to 64 resources and 1 MiB total; each file is limited to 256 KiB.
`resolve` returns the bytes as Base64 and reports a media type. Handles are private to the Lua state that loaded them,
become stale after release, and are discarded when the mod unloads. This lets scripts read data and small binary
resources; it does not by itself register images, models, or sounds with the games' native asset loaders.

## Native file overrides (`resources.override`)

```lua
local override = assert(game.resources.override({
  path = "resources/dungeon/room.pac",
  game_path = "dun/pack/maindat.pac"
}))
-- Remove it early if needed; all overrides are also removed when this mod unloads.
assert(game.resources.unoverride({game_path = "dun/pack/maindat.pac"}).removed)
```

An override replaces a file that the PC port's native data reader already knows how to open. `game_path` is a relative
path in the game's data tree; it is case-insensitive and accepts `/` or `\\` separators. The source must be a regular
file below the package's `resources/` directory, and the same traversal and symbolic-link checks apply. A mod owns its
override until it removes it or unloads; another mod cannot take or remove that path. Limits are 64 overrides per mod,
512 across all mods, and 128 MiB per source file.

For an indexed file, the adapter uses the replacement only when it is non-empty and no larger than the retail file,
except on Chronicle as described in [Chronicle: overrides larger than retail](#overrides-larger-than-retail-chronicle).
Bounded exceptions support new native asset paths: Chronicle accepts `dun/monstor/<name>.chr` and `.stb` up to 2 MiB
after sector padding; Chronicle Two accepts `dungeon/monster/<name>.chr` up to 3 MiB.

Chronicle Two runs its scripts as Luau modules (from ChronicleTwo `7a7d7f29`), so its data reader no longer loads `.stb`
files: a `.stb` override registers but the game does not read it. Both use native 15-character monster names with
letters, digits, `_`, `-`, or `.`. Chronicle can alias a reserved `gedit/s60`–`gedit/s69` directory to indexed built-in
field assets when a mod registers a copied location; owned overrides inside that target directory can replace individual
files. See [Chronicle native locations](world.md#native-locations-chronicle).

Chronicle Two also reads explicitly registered, previously unindexed files under `map/` with `.cfg`, `.efp`, `.ipk`,
`.map`, `.mpk`, or `.sky` extensions (also with a trailing `.json`, the form its converted tables take), up to 3 MiB
after sector padding. `locations.register` can append a standalone interior map to Chronicle Two's loaded native map
catalog when the mod owns its required map assets; see [Chronicle Two authored
locations](world.md#authored-locations-chronicle-two) for registration and transition details. Replacements still need
the exact format expected by that game's loader.

This does not register a standalone dungeon or animation, and it does not validate model formats or rig compatibility.
ChronicleTwo-Script `add` assets and format conversion remain unverified for the PC runtime.

## Overrides larger than retail (Chronicle)

On Chronicle (the PC port only; PS2 builds keep the retail-size rule), an override of an existing file may be larger
than the retail file when its kind allows it and the game has room for it where it reads it:

| Kind | Limit (bytes) | Read into |
|---|---|---|
| `.mpd` floor pack | 6,399,999 | the map read buffer (the game stops at 6,400,000) |
| `.cfg` floor script | 1,048,576 | a temporary block at the end of the map model buffer |
| `.chr` character, monster, weapon | 16,777,216 | the read buffer, or an arena block advanced by the file's size |
| `.stb` script | 4,194,304 | the read buffer, then copied into the monster or event script arena |
| `.mes` text | 1,048,576 | the battle, edit or system message buffer (about 670 KB of room in a dungeon); `opdat/*.mes` 68,992 |
| `.snd` sound pack | 16,777,216 | the sound read buffer |
| `.scn` Georama scene | 8,388,608 | the edit NPC buffer |
| `.edt` Georama layout | 65,536 | a 64 KiB block (retail: a 4,000-byte stack buffer) |
| everything else (`.mds`, `.img`, `.pak`, `.pac`, `.bin`, ...) | retail size | fixed layouts |

Besides the kind's limit, the file rounded up to 2,048-byte sectors must fit the room left in the arena block it is read
into; the port checks this when the file is read. A larger file that is used logs
`moonmod: override for <path> grows <retail> -> <size> bytes (limit <limit>, buffer room <room>)`. One that is not logs
`moonmod: refused override for <path>: ...` with the reason, and the retail file is read instead. With no override active
the game reads exactly as before. [dc1tk](https://github.com/Jeffiest/dc1tk) `mod-pack --port` packages edits against
these limits.

## Override reload and notices (Chronicle)

About once a second, the game checks every override file it was given. When one has been rewritten on disk (a new
dc1tk build, an edit), the game picks it up: it logs `moonmod: reloaded override <path>`, shows "Mod file reloaded"
on screen, and reads the new bytes the next time it loads that path (for a floor, the next floor). A replacement the game
refuses when it loads (too big for its kind or its buffer) is shown on screen once, as "Mod file not used: <path>", as
well as logged. dc1tk `mod-pack --install <save>` writes the package into `<save>/mods` and turns it on in
`<save>/moonmod/profile.json` (backup `profile.json.before-<id>`). A new override file, or a changed `main.lua`, needs
the game restarted.

## Package audio (`audio.register`, `audio.play`)

```lua
local sound = assert(game.audio.register({id = "arrival", path = "resources/audio/arrival.ogg"}))
local voice = assert(game.audio.play({id = "arrival", volume = 0.8, pan = -0.2}))
assert(game.audio.stop({handle = voice.handle}).stopped)
```

Mods can register WAV, FLAC, or Ogg Vorbis files under `resources/audio/`, then play their own registered IDs through
the game's mixer. `audio.register` requires `content.register`; `audio.play` and `audio.stop` require `game.write`.
Playback returns an owner-scoped handle; another mod cannot stop it. Calls accept `loop` (default false), `volume` in
`[0, 1]` (default 1), and `pan` in `[-1, 1]` (default center). Each package can register 32 sounds, retain 64 MiB of
decoded audio, and play 8 voices at once. Framework-wide limits are 512 sounds, 256 MiB decoded audio, and 128 voices.
Source files are limited to 16 MiB and decoded tracks to 32 MiB each.

Registration and voices are released when a package unloads. This API mixes package audio into the game's existing
output; replacing native music banks or sound effects is a separate asset-loader API.

## Retail sound and music (`audio.se_play`, `audio.bgm_play`, `audio.music_set`, Chronicle)

- `game.audio.se_play{se, volume?}` plays one of the game's own sound effects by its table number (0-4095; `volume` 0-127,
  default the table's).
- `game.audio.bgm_play{set, track?}` loads music set `set` (0-255) and plays track `track` (default 0).
- `game.audio.bgm_stop()` stops the music.
- `game.audio.music_set{sequence, path, gain?, loop?, loop_start?, loop_end?}` plays a package recording (WAV, FLAC or OGG
  under `resources/audio/`) in place of a game music sequence. `sequence` is the sequence name the soundtrack option uses
  (`DC_AUDIO_TRACE=1` prints them). It works whichever soundtrack is chosen and takes effect the next time that sequence
  starts. `audio.music_clear{sequence}` takes it back, and unloading the mod takes back all of its music. Two mods
  cannot replace the same sequence.

```lua
game.audio.music_set({sequence = "e01a_a", path = "resources/audio/norune.ogg", loop_start = 4.0})
```

## Game text (`text.*`, Chronicle)

Messages are keyed as in the language files (dc1tk `lang-export`, upstream `docs/LOCALIZATION.md`): the message file
key, a dot and the message id, for example `dun.message.old_data.dungeon.0`. `game.text.set{key, text}` replaces a
message (up to 4096 bytes, in the language files' notation, `{insert1}`, `{cyan}` ...), over the language file's text,
for as long as the mod is loaded. It applies when the message file next loads, which for most messages is the next
scene. `game.text.clear{key}` takes it back. `game.text.get{key}` gives the text and its `source`: `mod:<id>`,
`language file`, or `disc` (then `text` is null). Two mods cannot set the same message. Requires `content.register`.

```lua
game.text.set({key = "dun.message.old_data.dungeon.0", text = "{icon-jar}\"{insert1}\" found!"})
```

## Mesh and texture replacements (Chronicle)

Chronicle's renderer also supports package-owned 3D mesh replacements outside the Lua API. Put `models/<texture>.obj` or
`models/<texture>.glb` in an enabled package; use `<texture>__<vertex-count>v.obj` for a source-vertex-specific
replacement. An optional sibling JSON file accepts `scale`, `rotate_deg`, `offset`, and `flip_v`. Enabled packages can
also supply `textures/<texture>.png` to replace the matching native texture. The renderer keeps the native material
strips and follows native character skinning. Later packages in MoonFactory's resolved load order override earlier
package assets; a matching exact-vertex file takes precedence over a generic texture file.

Set `DC_DUMP_MODELS=1` before launching to dump source meshes as OBJ files into `<save-root>/mods/_dump/models`; each
file name includes its source texture and vertex count. Model and texture files larger than 64 MiB are skipped. Direct
runtime GLB loading flattens mesh instances in the selected scene, applies node hierarchy transforms, expands sparse
accessors, and converts triangle, strip, and fan primitives into the renderer's triangle list. Point and line primitives
are skipped. The package-generating editor is documented in [MODEL_REPLACEMENTS.md](../MODEL_REPLACEMENTS.md).

The native 2D item/weapon icon path uses the `itemicon` and `wepicon` atlases; package PNG overrides named
`textures/itemicon.png` and `textures/wepicon.png` repaint them while keeping the native icon rectangles and layout.
This does not register new per-item icon entries or alter UV rectangles.

## Monster model resolution (`models.*`)

```lua
local model = assert(game.models.resolve({monster_id = 0}))
print(model.model, model.source)
for _, asset in ipairs(model.assets) do
  print(asset.slot, asset.game_path, asset.overridden)
end
```

`models.resolve({monster_id = id})` reads the current port's native monster table, including registered enemy variants.
It returns the model and script names, the `.chr` path used by the native loader, and whether that path has a resource
override. Chronicle uses `dun/monstor/<name>.chr`; Chronicle Two uses `dungeon/monster/<name>.chr`. Both ports support
`models.resolve({id = model.id})` for package model bindings. It returns the binding's model and script paths, active
override state, template monster id, and availability status.

Both games can bind a new monster model path to a package asset, then use it in a new native-backed enemy definition.
Chronicle Two uses `dungeon/monster/`; Chronicle uses `dun/monstor/`:

```lua
assert(game.resources.override({
  path = "resources/moon-sentinel.chr",
  game_path = "dun/monstor/moon_sentinel.chr"
}))
local model = assert(game.models.register({
  id = "moon-sentinel-model",
  template_monster_id = 0,
  model = "moon_sentinel"
  -- Optional: script = "moon_sentinel_ai" when its .stb is also overridden.
}))
local enemy = assert(game.characters.register({
  id = "moon-sentinel",
  name = "Moon Sentinel",
  kind = "enemy",
  model = model.id,
  stats = {hp = 450, attack = 80}
}))
```

`models.register` requires the registering mod to own the `.chr` override. Chronicle's pack must provide `info.cfg`;
Chronicle Two's pack must provide `<model>.cfg`. A custom `script` additionally requires an owned `.stb` override; when
omitted, the template's native script is inherited. On Chronicle Two a custom `script` cannot load, because the game
runs monster scripts as Luau modules; inherit the template's script there.

`models.unregister({id = local_model_id})` removes the logical model binding when no registered character or existing
embedded-motion definition refers to it; it leaves the separately registered resource overrides in place for
`resources.unoverride` or owner cleanup. The character's native table row points at these asset stems. Chronicle can
load a custom model after floor entry when a slot is free in its 24-model floor table; Chronicle Two loads it through
the native monster manager.

Chronicle bounds package `.chr` and `.stb` reads to 2 MiB after sector padding; Chronicle Two uses a 3 MiB limit.
`models.replace({monster_id, model})` changes the `.chr` model stem on a native monster-table row, and
`models.remove({monster_id})` restores the value captured before that mod's first replacement. Replacement requires the
calling mod to own the matching `resources.override` path (`dun/monstor/<model>.chr` in Chronicle or
`dungeon/monster/<model>.chr` in Chronicle Two), and another mod cannot replace or remove its binding.

A row whose model is loaded on the active dungeon floor cannot be changed until that floor is left. Unloading the owning
mod restores its native model binding. `resources.unoverride` refuses to remove a `.chr` path that an active native
model replacement still uses, and it protects `.chr` and custom `.stb` paths held by a registered model because native
model definitions persist until process exit. The API checks ownership and size but does not validate the model format
or rig compatibility. Existing embedded-motion playback remains at its verified baseline; it is not expanded by model
binding removal.

## Animations (`animations.register`, `animations.play`)

Both Chronicle games expose animation operations for motion entries embedded in an owned, registered `.chr` model. This
binds existing model motion data; it does not author new motion data or load a standalone animation file. This
implemented playback path is retained as a frozen baseline: animation API expansion, standalone animation authoring, and
fighting-style authoring are deferred until model rigging is in scope.

```lua
local animation = assert(game.animations.register({
  id = "sentinel-idle",
  model = model.id,
  motion_index = 0
}))
local playback = assert(game.animations.play({
  animation = animation.id,
  entity = spawned.entity_handle
}))
local stopped = assert(game.animations.stop({entity = spawned.entity_handle}))
```

`animations.register({id, model, motion_index})` binds an integer motion index from 0 to 255 to a stable mod ID. `model`
must be a `models.register` entry owned by the same mod, with its `.chr` override still active. The API defers
motion-table validation until a compatible model is loaded. `animations.play({animation, entity})` accepts only a living
enemy spawned by the same mod with `characters.spawn`, using the model bound to that animation.

Chronicle checks the loaded motion table on each rendered part and queues a native restart request; Chronicle Two checks
the loaded motion table on the root and linked parts and calls the native motion setter. `animations.stop({entity})`
only acts on a playback started by the caller. If native AI has switched to another motion, the adapter leaves it alone;
otherwise it restores the previous motion request when available. Despawning an animated enemy releases its tracked
playback state, and owner unload stops tracked playback before despawning live enemies. The response reports stable IDs
and indices rather than native motion names because game data may encode those names in a legacy non-UTF-8 character
set.

These APIs play motion clips already embedded in a registered model. This playback support is kept at its verified
baseline; further animation work, standalone animation authoring, and fighting-style authoring are deferred until model
rigging is in scope. Playable-character animation control remains unsupported.

## Playable-character motions (`animations.player_register`, Chronicle)

`animations.player_register({id, file})` adds a mod's own motion to a playable character. `file` is a `.json` file
under the package's `resources/` (up to 4 MiB) in the `moonmod-motion` v1 format:
`{format = "moonmod-motion", version = 1, character, length (1-600 frames), speed?, tracks = {{bone, type =
"rotation"|"translation"|"scale", keys = {{frame, w, x, y, z}...} or {{frame, x, y, z}...}}}}`, rotations as the game
stores them, frames rising from 0 to `length`. Whenever that character's model loads in a dungeon, each of its
registered motions is appended after its last native frame (on the model and its shadow) and its first motion set
grows by one motion number per file; bones a file leaves out hold their idle pose. A registration made while the
character is loaded applies at once. `animations.player_unregister({id})` takes one back (unloading takes all);
`animations.player_list()` lists the mod's motions with the motion number each has on the loaded character. Moves
play them by name (`player.moves_set`, `animation`). A mod registers up to 64. The tools in `tools/anim` write
these files from a character's own rig; see the [animation guide](../ANIMATION_GUIDE.md) and
[Gauntlet animations](../GAUNTLET_ANIMATIONS.md).

## Monster motions (`animations.monster_register`, Chronicle)

`animations.monster_register({id, file, model, hits?})` adds a mod's own motion to a native monster model (`model`,
the native model id, as `entities.query`'s `native_model_id`: 1 the Skeleton Soldier, 3 the Dasher). The file is the
same `moonmod-motion` v1 format, its `character` the model's file name (`e03a`, `e06a`); bone names may keep a frame's
attribute (`knife__m`). Whenever a floor loads the model, its registered motions are appended after its last native
frame, on the model, its shadow and each part it carries, in the order they were registered, and its first motion
set grows by one motion number for each. A registration counts from the next load of the model (the next floor), so
register at load. `hits` (up to 4: `{bone, radius (default 2, up to 40), from, to, damage (default 1, up to 10)}`)
become damage spheres on the named frame of every monster of the model as it spawns, live while the motion's frame
lies between `from` and `to` (the motion's own frames): each deals the kind of hit of the monster's first native blow,
and that blow's damage times `damage`. `animations.monster_unregister({id})` takes one back from the next load
(unloading takes all); `animations.monster_list()` lists the mod's monster motions with `motion` (the number to give
`SET_MOTION`) and `start` (its first frame, what `CHK_MOTION_FRM` reads while it plays) once a loaded floor model
carries them, nil before. A mod registers up to 64. Vigil's rolls and attacks are an example
(`tools/anim/vigil_monster_moves.py`, `MONSTER_MOVES` in `mods/moonmod.vigil/main.lua`).
