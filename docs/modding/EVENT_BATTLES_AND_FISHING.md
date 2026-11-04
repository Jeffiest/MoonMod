# Event battles and fishing: survey and plan

Two native systems no mod can reach yet. This page records where they live in the game and the smallest engine
operations that would open them to Lua. It belongs with [Extending the engine](EXTENDING_THE_ENGINE.md). Paths are in
the Chronicle tree; line numbers are from Chronicle `9418a550`'s forked game and may drift.

## Event battles (the button-prompt "duels")

The game calls them event battles (EB). A story scene's town script drives them; the dungeon's battle script table
has none. Which scenes use them is in the script data, not the C++, so a scene is found by its script (Seda's on
Divine Beast Cave floor 8 is one).

**The script natives** (`ext_func_info[]`, `editloop3.cpp`): `EB_INIT` 950 (speed), `EB_SET_KEY` 951 (time, buttons,
mode), `EB_LOOP` 952, `EB_SET_MOTION` 953, `EB_DEBUG` 954, `EB_INTRO_START/LOOP/END` 955-957, `EB_FINISH_SOUND` 958.
The script calls `EB_LOOP` each frame until it returns non-zero, and branches on the answer: -1 failed, 1 passed,
2 passed with every press "cool".

**The loop** (`EBLoop`, replaced by the port in `port/src/ebattle.cpp`):

- Each key's distance is `(eb_count - key.frame) * speed`, with `speed` four times `EB_INIT`'s argument.
- A key is live while the distance is between -16 and 48, about 4 frames early to 12 late at the usual speed. A press
  under 24 counts as cool.
- A scene fails on a wrong button, a press with no key live, or a key that passes unanswered. The music fades and
  `EB_LOOP` returns -1 after 80 frames.
- At the end the fanfare plays and the result is 1 or 2.

**What exists already.** The port's settings have **Always Win QTEs** (`Config::qte_always_win`, Options > Game). It
ignores every failure and reports 2. A player who wants the prompts gone needs no mod.

**What a mod would add: easier prompts, not none.** Proposed as one more `player.tuning_set` field, so it is owner
scoped and goes away with the mod:

| `event_battle` | Effect in `EBLoop` |
| --- | --- |
| `"normal"` | As retail. |
| `"wide"` | The live window doubles: -32 to 96, cool under 48. |
| `"forgiving"` | `"wide"`, and a wrong extra button is ignored rather than failing the scene. |
| `"auto"` | Each key is pressed for the player on its frame (`active->pressed = active->buttons` when the distance first goes past 0), so the scene plays out with every hit shown, cool. |

The engine change is small: read the combined tuning at the three constants and the two failure tests above. Owners
combine by taking the most lenient. A test in `moonmod_tuning_test.cpp` can drive `EBLoop` with a fake key table, as
the port's own tests do. Once it lands, Modern Cloud gains a *Button prompts* setting.

## Fishing

**Files.** `fishing.cpp` (line, float, hook, bait, spawns) and `fish.cpp` (each fish's behaviour, sizes, points); the
player's side is the `chara_fishing` state machine in `EdMoveChara` (`ebattle.cpp`).

**How a catch goes.** The town script loads a spot (`LOAD_FISHING_DATA` 998, the spot number and its bounds) and
switches to fishing mode (`GOTO_FISHING` 997). The player casts with Cross. Each fish nearby walks a small machine:
notice the bait, eat, bite. Each step's chance is the fish's affinity for that bait times 0.3 or 0.5, and it leaves
with chance 0.1. Striking while a fish only nibbles loses the bait one time in five; a fish that escapes takes it
three times in ten. A landed fish adds its points (`SaveData->AddFishingPoint`, capped at 9999) and its size to the
record (`SetFishingRank`, 64 entries).

**Data.**

- `fish_info[18]` (`fish.cpp`): each kind's model size, size range, points range and bait affinities. Models are
  `chara/f01a.chr` to `f18a.chr`. Kinds 5 and 17 (Mardan Garayan) are rare, gated by a time-of-day interval.
- `esa_info[13]` (`fishing.cpp`): bait item numbers and how far each draws a fish (Evy 193 draws from 50, Petite Fish
  190 from 40; also Mimi 197, Prickly 199, Carrot 186, Potato Cake 187, Minon 188, Battan 189 and fruits). The rod
  is item 185.
- Which fish swim at each spot is code, not data: `FishingLoadFish` switches on spots 0-4 with percentage rolls for
  four or five fish.
- The prize exchange (`exitemlst[35]` in `shop.cpp`) trades fishing points for items.

**Proposed operations** (a `game.fishing` domain, Chronicle):

| Operation | What it does |
| --- | --- |
| `fishing.get()` | Points, the record table, the Mardan Garayan count, and the live state when fishing (`state`, `spot`, the fish nearby with kind and size). |
| `fishing.fish_set({kind, size_min?, size_max?, points_min?, points_max?, affinity?})` | Owner-scoped edits to `fish_info`, restored on unload. |
| `fishing.bait_set({item, radius})` | Edits `esa_info`; a registered mod item can become a bait. |
| `fishing.spot_set({spot, fish = {{kind, chance}, ...}, count?})` | Replaces a spot's roll in `FishingLoadFish` with a table. |
| `fishing.points_add({amount})` | Through `AddFishingPoint`. |
| `game.fishing.caught` | Event: `{kind, size, points, spot, bait}` from the RESULT state. |
| `game.fishing.lost` | Event: `{reason = "escaped" | "bait", spot}`. |

With those, a **Fishing Derby** mod is Lua only: a villager posts the day's wanted fish, `caught` checks it, prizes come
through `items.give`, and a weekly record board sits in mod storage. Rare fish by weather or season, new baits from
the shops and a mod fish (a registered model on a kind's slot) follow from the same calls.
