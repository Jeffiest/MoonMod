# Vigil (prototype S1)

Souls-lite combat for Chronicle's story game: slow, deliberate fights where you read an enemy, then guard or evade,
then punish. This is the first prototype. It uses only what the engine already offers. The plan, the findings behind
it and the engine work still to come are in [`VIGIL_PLAN.md`](../../VIGIL_PLAN.md).

## What it does

| | |
| --- | --- |
| **L2: evade** | A roll the way the stick points, or a backstep with the stick at rest. Out of a run, Toan's roll pushes off whichever foot is leading. Locked on, with the stick to the side, he rolls sideways and keeps facing the enemy. The roll leaves the ground 0.11 s after the press, and the camera keeps up with it. Xiao, Ruby and Osmond tumble and hop back instead. You can't be hit while evading. Each evade costs **35 weapon gauge** and has a 30-frame cooldown. With the starting Dagger, four quick evades in a row empty the gauge, and L2 then waits for it to refill to 35. An evade can cut a swing short, but only 6 frames after its blow lands, so you commit to a swing. |
| **Toan's attacks** | On top of his combo: **R2** a heavy blow, or partway through the combo a finisher (after two blows, or three). Locked on, attack with the stick **toward** the enemy to lunge, or **away** to strike while backing off. Attack out of a run for a running attack, late in an evade for a follow-up, and while guarding for a counter. Each is its own motion file, a slot you can fill with your own (below). *Toan's attacks* in the settings turns them off. |
| **The weapon gauge is your stamina** | It's the gauge under your weapon at the bottom left. Dark Cloud already spends it on combo swings (a follow-up needs 20 and costs 25), and refills it at your weapon's Speed. |
| **Guard (lock on, then hold R1)** | The game's own guard. While you hold it, the gauge recovers at a quarter of its speed. |
| **Enemies fight smarter** | Dashers and Skeleton Soldiers circle at a distance and take turns: one attacks at a time. They sidestep, roll aside or step back from your swing and punish the whiff, feint (a wind-up broken off into a sidestep, then the real swing), rush in from the edge of the circle, string up to three blows, and hold a wind-up through your roll to hit you as it ends. A Skeleton Soldier often blocks your swing on its shield and strikes back. Each has a new attack of its own now and then: the Skeleton's whirling slash (one full turn, blade out) and the Dasher's pounce (a leap that slams its mace down in front of it). The rolls and attacks are Vigil's own motions (`resources/anims/e03a_*`, `e06a_*`, from `tools/anim/vigil_monster_moves.py`), added to the monsters by the engine. Other monsters keep their own AI. *Enemies fight smarter* in the settings turns it off, and turning it on takes over the monsters already on the floor. |
| **Enemies hit hard** | ×2.5 damage. |
| **Shorter hit stun** | A hit stuns you for 40% of the usual time. In Dark Cloud the stun is also your protection after a hit, so the next hit can land sooner. Don't get hit twice. |
| **Slower character switches** | ×2 the wait, so a switch isn't a free escape. |
| **Vigil World preview** (off by default) | Each floor is two zones on one map, joined by a locked gate. A monster in the first zone carries the gate's key: kill it, pick the key up and walk through, with no load. A gate once opened stays open on later visits, like an opened chest. Turn on *Vigil World preview* in the settings before a new game (it needs *The same floors every visit*): a save keeps the choice it first went into a dungeon with, so a story save already under way stays a normal Dark Cloud save, and one started with Vigil World keeps it. Each zone has a **shrine**, a spring against a wall: walk up to it and it lights; step into its water and press Square (E on the keyboard) for its panel. The water quenches thirst but doesn't heal. The panel offers *Rest* (heal the party and cure its ailments; the floor is built again with its monsters back, chests and gates as you left them, and you wake at the shrine), *Travel* (the dungeon's map opens with every other lit shrine to pick, on any floor; L1/R1 step between them, L2/R2 between maps, Cross goes), *Leave* (to the dungeon's town) and *Level up* (Circle stays). While the preview is on, a shrine is the only way back to town: the Escape menu refuses and the exit gate leads on. Walking in from town starts at the entrance, floor 1 (to start at a shrine, pick it on the town's map); the last shrine you reached is where you wake after a knockout (healed, the monsters back). The half of your Gilda a knockout takes, and your weapon's unspent ABS, lie where you fell, a pile of gold on the corner map and a mark on the map: walk up to it to take them back, before you fall again. A shrine's *Level up* opens the shrine tree on the Journal's Character page: spend Gilda on Vigour (max HP for the party), Endurance (the gauge refills faster) or Guard (guarding slows the refill less), only at a shrine. No monster starts near a shrine, and none steps into its circle (about two and a half cells around the spot in front of the spring): a chaser stops at the edge, so you wake and rest in peace. Monsters **scale** too (on by default with the preview, *Floor scaling*): each zone has a base level two steps deeper per floor, your level comes from your weapon's attack, and a monster is fought at whichever is higher of its zone's level and yours less two (*scaling gap*). A zone you have outgrown keeps up with you, with more life, harder hits and a little more reward, so nothing dies in a hit or two. Each dungeon becomes **one continuous map** too (*Regions*, on with the preview): every floor is a zone of it with its own monsters, atla and chests (Divine Beast Cave: floors 1-15; Gallery of Time is two maps, 1-12 and 13-25), and the entrance has no floor menu or loading card: the cave's door opens and you walk in, to floor 1, the village still in sight through the doorway behind you, with no walk down the stairs. The cave is there through the door the first time too, and the way out shows the village in daylight. Once the door has slid open it stays open: walk up to it facing in and you walk straight into the cave, no button. Matataki's forest path is connected the same way once you have walked into Wise Owl Forest (the forest isn't seen from the path before the first visit). The other towns' dungeons are reached from the world map, so they have no doorway. With Vigil World the towns lie along one **road**: walk out of a town's gate (where the world map used to open) and a panel asks which way, back or on to the next town (Norune, Matataki, Queens, Muska Lacka, Yellow Drops) or into the dungeons the world map reached (Shipwreck from Queens, Sun and Moon Temple from Muska Lacka, Moon Sea and Gallery of Time from Yellow Drops, each at floor 1); the trip is a cut, no loading card. *Stay* (or Circle) stays; walk off the gate and back to be asked again. Walk back out to the village and in again and floor 1 is as you left it, its monsters where they were. On a map whose first floor has the Fairy King's opening (Divine Beast Cave), he waits a few steps down the first corridor instead of the scene playing as you arrive: walk up to him and press Square to hear it. The story floors, where the game's own scenes and bosses are (Divine Beast Cave's 4, the skeleton; 8, Seda; each midway boss; and each last boss, such as Dran's 15), stand behind **smoke** (the floors that only lock the party to one character, such as Divine Beast Cave's 11 for Xiao, are ordinary zones): a gate no key opens, a wall of pale smoke in front of its door. Walk up to it and choose *Go through* to play that floor as the game has it; at its far gate (the one that wants the floor's key) choose *Leave* to come back to the map at the next floor's shrine, and the smoke is gone for good, its small zone a walk-through. Every arrival at a shrine (a rest, a wake, travel, the town's map, out of the smoke) is a teleport in the escape item's light, not a walk down the stairs. The back floor's key (Dran's Crest in Divine Beast Cave) drops from any monster on the map, once: it stays with the save through knockouts and trips to town (given back on your next visit until the back floor is entered), and a second one found pays 300 Gilda instead. The **Fairy King** stands beside the shrine of each zone whose floor has his scene (Divine Beast Cave's 3, 5 and 7) until you have heard it: walk up to him and press Square to talk, the scene plays, and you are back at that shrine afterwards. A map's exit gate leads past its last floor, entering by one of its later floors starts you at that floor's shrine, and the Floor number in the corner follows the zone you are in (`VIGIL_PLAN.md` section 9, W1.1 to W2). |
| **The map** | Select or L3 (M on the keyboard) in a dungeon pauses on the whole map of where you are, as far as you have explored it: rooms and roads, its shrines (lit or not) and locked gates once you have found them, and you. Move the cursor with the pad, jump between marks with L1/R1, and put a waypoint with Triangle; the minimap flags it too. What you have explored is kept with the floor, so it is still mapped next time. In the dungeon's town, L3 or M opens the maps of every place you have explored there (L2/R2 between them; Select stays the Georama button), and Cross on a lit shrine travels straight to it. On a map as big as a region, the minimap shows the part around you and scrolls as you walk. *Map screen* in the settings turns it off. |
| **The same floors every visit** | Each floor keeps the layout it had the first time you went down it, saved with your save slot, so a floor is a place you learn instead of a new maze each time. Its monsters come back, but a chest you opened stays opened (except the floor's map and magic crystal, which only work on the visit you find them). Back floors follow their floor. Demon Shaft stays new every time. *The same floors every visit* in the settings turns it off. This is the first step toward one continuous dungeon (`VIGIL_PLAN.md` section 9). |
| **No Stamina power-up from enemies** | In this game the "Stamina" ailment is actually a power-up (double attack, defense and gauge refill), and some enemies hand it out. Vigil turns that off. |

Every number is a setting in the Mod Manager. **Check** on the mod's Actions page shows what's set right now.

Vigil sits out Dark Genie's Gauntlet. During a run it hands back L2, its tuning and its damage formula, and takes them
again afterwards.

## Not yet (needs engine work, see the plan)

- The guard still blocks **everything, from every side, for free**. A front-only guard, a gauge cost per blocked hit,
  guard break and parry come with E1.
- **A hit still refills the gauge to full**, and the first swing of a combo is free. E2 fixes both.
- Vigil can't read the gauge yet (E3), so there's no Exhausted state of its own.
- With a keyboard, pick your guard key in the settings (*Keyboard key you guard with*) so the slower recovery works.

## Playtest (gate S1)

Divine Beast Cave floors 1-3 as Toan, Vigil's defaults, nothing else gameplay-changing on.

- [ ] L2 with the stick pushed rolls that way; at rest, he backsteps. Neither can be hit.
- [ ] Locked on, L2 with the stick to the side rolls sideways, still facing the enemy.
- [ ] A Dasher circles and waits its turn, and punishes a missed swing.
- [ ] A Skeleton Soldier blocks some swings on its shield and ripostes; attacking it from the side or after its swing gets through.
- [ ] Dashers and Skeleton Soldiers sometimes roll aside from a swing; the roll looks like a roll, not a slide.
- [ ] The Skeleton's whirl and the Dasher's pounce read clearly before they land, can be rolled through, and hurt about as much as their usual blows.
- [ ] Four quick evades in a row empty the gauge, and L2 does nothing until it refills.
- [ ] L2 right after a swing's blow cuts the swing. L2 before the blow doesn't.
- [ ] Holding the guard visibly slows the gauge's refill.
- [ ] Trading hits with a Skeleton Soldier loses. Evading or guarding and then hitting wins.
- [ ] Getting hit, then hit again soon after, is possible (the shorter stun), and it feels fair rather than cheap.
- [ ] R2 swings the heavy; R2 after two or three combo blows plays a finisher instead.
- [ ] Save, go down a floor, leave for town and come back (or load the save): the floor has the same rooms and the
  same chests as before.
- [ ] Note what feels wrong, with numbers: which setting, which value felt right.

Record results in `tools/tests/vigil/playtest-log.md`.

## Your own moveset for Toan

Each of Toan's attacks plays a motion in `resources/anims/` (`toan_heavy`, `toan_finisher_2`, `toan_finisher_3`,
`toan_run_attack`, `toan_lunge`, `toan_back_attack`, `toan_roll_attack`, `toan_guard_counter`). The ones shipped are
copies of the Gauntlet's hand-made attacks. If you own Elden Ring, `tools/anim/reference/import_motion.py --moveset`
swaps a whole set of its attacks onto these slots in **your save's copy** of Vigil, never the mod as shipped. Each
attack's blow is lined up with the slot's own, so the hits still land on the swing. `--restore` puts the shipped
motions back. See [`tools/anim/reference/README.md`](../../tools/anim/reference/README.md).

## Tests

```bash
lua tools/tests/vigil/test_vigil.lua
```

217 checks against a fake adapter that refuses what the real one refuses: the evades for all six characters, Toan's
side rolls and attacks, the guard, the enemy brain (it really stops: an empty native argument list is refused) and the monsters' own motions, the same floors every visit, their opened chests, the zones preview, its shrines, floor scaling, regions, the map and waking at the last shrine,
settings, the fallback to the engine's own dodge when the motions can't load, sitting out the Gauntlet, and the
shipped motion files.

The motions in `resources/anims/` are copies of the Gauntlet's (authored with `tools/anim`; see
[`docs/GAUNTLET_ANIMATIONS.md`](../../docs/GAUNTLET_ANIMATIONS.md)).
