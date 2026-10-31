# Opar: the seventh playable character

Opar is a frog mage from the Moon Sea: a squat, spotted, big-lipped brawler of a wizard who fights with a gnarled
staff and his own spit, and who can, for a few seconds, leap, slam the ground and swell into the giant Opar of Dark
Cloud's own monster list (#98, model `e104a`). He joins **Dark Genie's Gauntlet** first; the main game comes later,
if ever.

How he is checked and graded is [OPAR_VERIFICATION.md](OPAR_VERIFICATION.md). How his model is made and built is
[art/opar/README.md](../art/opar/README.md) and [tools/chr/README.md](../tools/chr/README.md).

Everything here is uncommitted Gauntlet work until the Gauntlet is finished.

---

## 1. Where he stands (2026-10-29)

| Piece | State |
|---|---|
| Pack pipeline (`tools/chr`, the DC1 toolkit fixes, the override fix in the engine) | Done, round-trip tested |
| Model, paint, weights (`art/opar/make_opar.py` → `c07d.chr`) | Done, seen in game in Toan's slot |
| Model reworked (one sculpted skin, ~15,000 triangles; `art/opar/make_opar.py`) | Done; loads in his own slot (207,891 quadwords of the 840,000 the port carves) |
| Staff models, all six (`art/opar/make_staffs.py`, `tools/chr/build_weapon.py`) | Done; Tidecaller seen in hand in game |
| His own slot (phase 3) | Done 2026-10-29 (gate O3 passed), then opened up the same day: the engine takes up to ten registered playable characters (`characters.register_playable`); the Gauntlet registers Opar as the first (index 6) behind its **Opar** setting, fighting as Toan until phase 4 |
| Motions (phase 5) | Base set done 2026-10-30: every native motion of his is a frog's (`tools/anim/opar_moves.py` rewrites his pack's motion file): a squat with the knees bowed, a forward lean, the staff upright outside attacks; his own idle, waddle walk and hopping run. Wider hips (`art/opar/proportions.json`). His attack motions for the spits and the kit are made too (`--anims`). His own hurt, knock-down and death made 2026-10-30 (a recoil with the throat puffed; flipped onto his back with his legs kicking, rolling forward and hopping up; toppling belly-up, legs splayed): the death seen in game |
| Spit (phase 4, part) | Done 2026-10-30, on Toan's controls (the user's choice: separate moves, not Ruby's): A,A,R2 **Spit** (two globs), A,A,A,R2 **Gob** (three in a fan), a charge let go **Bubble** (one big slow glob), L2 at rest **Back Hop** (a hop back with a glob). Each glob is a blue blob from his mouth that splashes in blue sparkles where it lands (engine: a move shot's `from`, `cell`, `size`, and its `burst` on landing). His own motions for all four (`opar_moves.py --anims`) |
| Kit (phase 6, part) | Done 2026-10-30, each with its own motion: run+attack **Belly Slide**, guard+attack **Staff Swat** (a spin), L2 with the stick **Frog Hop**, attack late in an evade **Leap Strike** (a bonk, then a glob), locked on with the stick away + attack **Tongue Lash** (its first hit yanks the enemy in), R2 at rest **Croak** (half the gauge; what it hits is stunned 1.5 s). The engine's cap on a mod's moves went from 64 to 160 to fit him. Seen in game: the slide, the hop and the croak; the swat, the lash and the leap strike only in the headless tests. The Tongue Lash's item snatch is not built |
| Jump Slam and Opar Form (phase 6) | Built 2026-10-30, reworked the same day to one slam: a charge held to the top (1.5) with a full gauge; his own leap (`opar_jump_slam`), a cloud of smoke, the monster (`player.form_set`: its pack, `art/opar/make_form.py`, drawn at half size) slams down with its own press and gets up (`player.move_play`; a ring of 3x damage, knockback 9, an explosion), a puff of smoke and he is himself (`form_clear`). Back a minute later. Seen in game |
| Staffs as his weapons (phase 4) | Done 2026-10-30: the six registered at load (`weapons.register` on template 262, owner Toan; models `opst01`-`opst06`, icons from `art/opar/make_staff_icons.py`); he starts with Driftwood; any weapon that comes to him (chest, Warden, Gaffer) becomes the staff of the dungeon it came in, then rolls its rarity like any; Tidecaller is his Legendary (Frost, Echo, signature Riptide). Their own: Reed globs 20% faster, Coral globs go through to one more, Bog Oak's Bubble splash 40% wider (every Bubble now splashes), Moonpearl's slam back 20 s sooner, Riptide splits a glob that hits into three. The Coral in his hand in game; the icons registered but not yet seen in a menu |
| Menus | Done 2026-10-30: his round medallion portrait, his item-menu model (c07model.pak), the staffs' models, icons, names and descriptions in the weapon and item menus |
| Signature sky (phase 7) | Built 2026-10-30, shown with the Opar setting: Big Mouth (Gob of five), Bog Hop (the Frog Hop leaves a slowing puddle), Spitter (+20% damage), Old Toad (the Jump Slam heals a quarter), King of the Moon Sea (the slam back in 30 s, 50% wider). Checked in the headless tests; the sky screen not yet seen |
| Voice | Done 2026-10-30: none of the game's sounds fit (the user listened), so CC0 frog croaks and ribbits from OpenGameArt (`art/opar/sounds`, CREDITS.md) fill Toan's nine voice slots in his own bank, `sound/voice/voice106.snd` (`art/opar/make_voice.py`); the engine loads a registered character's own voice set (CharaVoiceSet) and reads its cues as his fight-as character's. Loads and plays without a fault in game; not heard yet |
| Joining (phase 7) | Built 2026-10-30: the first Moon Sea Warden a run beats raises *Opar of the Moon Sea* in the Allies (30 Moon Shards); bought, he is in every run as the Opar setting puts him; his star and his Signature sky stay hidden until then (or with the setting on). Checked in the headless tests |
| Companion | Built 2026-10-30: with the Companion setting he can be the companion, spitting his blue glob from range (engine: `party.companion_set` takes registered characters and a `shot`). Seen following Ruby in game; his spitting not yet seen |
| Balance (first pass) | Done 2026-10-30 on the numbers (`tools/roguelike/move_table.lua`: every character's mod moves, damage in weapon attacks per second of use): his globs raised to sit between the melee finishers and the shooters' (Spit 1.95/s against Toan's Launcher 1.58 and Xiao's Fan 2.36; Gob 2.50 against 2.20 and 3.37), Bubble 3.0, Belly Slide and Staff Swat up to the others' run and guard attacks, Big Mouth's five globs 1.1 each; he thirsts 30% slower. His staffs track Toan's swords dungeon by dungeon (8 to 50). Not yet measured in play (metric 7: floor clear times) |
| Field ability | Dropped (the user's call, 2026-10-30) |

---

## 2. How he looks in game

**Body** (built): blue-black spotted hide painted a shade lighter than the concept for the dungeon light, a tan belly
and throat with folds, half-lidded yellow eyes, big pink lips, gill spines, metal shoulder pads (moss on the left),
chest strap, belt and buckle, pouch, gourd, a green and purple loincloth, leather wraps, webbed hands and feet.

**Still to make:**

| Piece | Plan |
|---|---|
| Staffs | Six models, one per weapon (§4), made like the body (a Blender script per staff, built with `weapons.register` `model` into `commenu/weapon/<stem>.chr`). Each held in the right hand (`weapon` frame); the head of the staff glows in the weapon's `weapons.style_set` colour. |
| His own proportions | Shorter legs and a lower, wider stance than Toan's skeleton allows: move the leg joints in the bind pose (`.bbp`) and in his own motions (§5), the body re-weighted. Done with the motions, not before. |
| Shadow model | His own `c07s.mds` (a low-poly copy of his body) so the ground shadow is a frog's, not Toan's. |
| Blink | His eyelids blink through `TEX_ANIME` on his own head picture (two eyelid frames painted into `c07d02`), replacing Toan's lines. |
| Portrait | The round face from the concept, for the character switch, the run menu, the Journal's Character page and the HUD (`render.hud_icon_set`). |
| Spit | A green-blue water glob with a splash on impact: the player shots of Xiao and Ruby, tinted by the staff's colour, the `heal` or `sparks` burst recoloured for the splash. |
| Opar Form | The game's own Opar monster model and motions, with a puff of mist (`smoke` burst) going in and out. |
| Voice | Croaks: the Opar monster's sound bank (304) for his voice cues (`voice`, `shout`) and a wet slap for spit hits. |

---

## 3. How he plays

He is a **mid-range caster who is dangerous up close**: he spits from a few steps away, swats anything that gets
into his face with the staff, hops in and out, and saves his gauge for one big transformation.

**Base:** his native action is Ruby's: the attack shoots orbs at the locked-on target and a held attack charges a
bigger one. Opar's orbs are spit globs.

| Input | Move | What it does | Built with |
|---|---|---|---|
| Attack | **Staff combo** | Toan's swings with the staff (he keeps Toan's controls). | native |
| A, A, R2 / A, A, A, R2 | **Spit / Gob** | Two quick globs, or a three-glob fan, out of the combo. Aimed at the lock-on target. | `combo_finisher` moves, shot hits from his mouth (built) |
| Attack (held, let go) | **Bubble** | A slow fat bubble that bursts on the first thing it meets. | `charge_release`, one big shot with a `heal` splash (built; an area hit on the burst still to come) |
| Run + attack | **Belly Slide** | Throws himself forward on his belly, bowling enemies over. | `run_attack`, lunge 5, low `hits` with knockback, `slam` trail (built) |
| Guard + attack | **Staff Swat** | A spinning bonk that knocks attackers back, his answer to being crowded. | `guard_attack`, spin 1, wide `hits`, knockback 6 (built) |
| L2 + stick | **Frog Hop** | A long hop the way the stick points, with landing frames he can cancel into a spit. | `dodge`, his hop motion (built) |
| L2 at rest | **Back Hop** | Hops back and spits a glob at whatever he left behind. | `dodge_back` with a shot hit (built) |
| Special | **Jump Slam → Opar Form** | See below. | A held charge at the top (1.5) with a full gauge, `charge_release` ahead of the Bubble; `player.form_set`, `player.move_play`, a `smoke` burst (built) |
| Locked on, far + attack | **Tongue Lash** | Lashes his tongue at a far-off enemy and yanks it in, into a staff bonk. Out of a fight, it snatches an item from across a gap. | `lock_attack` (away), a long thin reach hit, `entities.knockback` pointed at him to pull it in (built) |
| R2 at rest | **Croak** | Puffs out his throat and croaks: enemies close by are stunned for a moment. Costs half the gauge. | `heavy`, a wide `hits` ring with a token hit (0.2) that stuns (`combat.status_add` stop) what it reaches, `shout` cue (built) |
| Attack late in a Frog Hop | **Leap Strike** | A high hop onto an enemy's head that bounces him off it into a spit. | `evade_attack`, a hit on landing, then a `shot` hit (built) |

**Jump Slam → Opar Form.** With a full action gauge, a charge held to its top (1.5) and let go makes him leap high;
at the top a cloud of smoke covers him and the giant Opar (the game's own monster) drops out of it, slams down (damage
and knockback all round him, an explosion) and heaves himself back up; a puff of smoke and he is himself again. He is
the monster only for the slam (the user's choice, 2026-10-30: no walking about as him). It costs the whole gauge and
comes back a minute later.

**Field ability.** Every character in a Dark Cloud dungeon opens something; Opar's spit douses fire and swamp
hazards. In the Gauntlet that is a `dungeons.set_character_blocks` part for him: a flame wall or poison pool that
only he can clear, placed as a detour, never on the only way (the same rule as the other six).

**Stats.** Fragile up close and strong at range:

| | Health | Defence | Damage | Water |
|---|---|---|---|---|
| Opar | as Ruby | as Ruby, –10% | as Ruby, +5% | drains 30% slower (a frog) |

Balance targets are in the verification document: his floors must clear within ±15% of the party's median.

---

## 4. His staffs

The Gauntlet gives each character one weapon at a time, growing by tiers, with found weapons and a Legendary.

| Staff | Where | Its own |
|---|---|---|
| Driftwood Staff | The starter (and Divine Beast Cave drops) | — |
| Reed Staff | Wise Owl Forest drops | Spit globs fly 20% faster |
| Coral Staff | Shipwreck drops | Globs pierce one enemy |
| Bog Oak Staff | Sun and Moon Temple drops | Bubble splash 40% wider |
| Moonpearl Staff | Moon Sea drops | The Jump Slam is back 20 s sooner (the form is one slam now) |
| **Tidecaller** (Legendary) | Found once per run, like the others' | Signature **Riptide**: a glob that hits splits into three that seek new targets |

They take attachments and grow ABS like every Gauntlet weapon, and wear like Ruby's rings. Each has a model (§2), a
name and colour (`weapons.style_set`), and an icon.

---

## 5. His motions

Toan's skeleton carries Toan's motions, so Opar already moves; these replace them with a frog's, written with
`tools/anim/moonanim.py` in `tools/anim/opar_moves.py`, each checked on a stick sheet, then in game with
`--screenshot-at`. He fights as Toan, so the game plays Toan's motion numbers on him from his own pack: the script
rewrites that pack's whole motion timeline (Toan's untouched), giving every native motion his posture and replacing
the idle, walk and run with his own. His attacks are mod motions (`animations.player_register` with `character =
"opar"`) played by his moves.

| Motion | Notes |
|---|---|
| Idle | Squatting low, belly rising and falling, a slow blink |
| Run | A hop-waddle, staff swinging |
| Spit ×2, Gob | Lean back, cheeks out, lunge the head forward |
| Bubble charge, release | Belly swells, then the release |
| Belly Slide, Staff Swat, Frog Hop, Back Hop | The moves of §3 |
| Jump Slam | Crouch, leap, slam |
| Hit, knocked down, getting up, death | His own, heavy and floppy |

---

## 6. The Gauntlet around him

- **Joining.** The first time a run beats the Moon Sea Warden, the **Allies** constellation of Norune Eternal shows a
  new star, *Opar of the Moon Sea*. Bought with Moon Shards, it puts him in every later run's party.
- **Signature sky.** Like the other six, bought with his own Marks (built): Big Mouth, the Gob fires five globs; Bog
  Hop, the Frog Hop leaves a puddle that slows enemies; Spitter, +20% damage; Old Toad, the Jump Slam heals a quarter
  of his HP; King of the Moon Sea, the Jump Slam is back in 30 s and slams 50% wider.
- **Companion.** When the Companion setting is on, he can be the companion: he spits at the lock-on target and never
  transforms.
- **Run menu, HUD, Journal.** He is listed and switched to like the others; his page in Journal > Character shows his
  skills.

---

## 7. Building it, in order

Each phase ends with its gate in the verification document.

| Phase | Work | Engine? |
|---|---|---|
| 1 | Pack pipeline, Toan round trip | Done |
| 2 | Model, paint, weights | Done (proportions and shadow come with phase 5) |
| 3 | **Playable characters past the six in the engine** (done 2026-10-29): a registry of up to ten (`characters.register_playable`), Opar the first; the party, the switch wheel, the status and equip pages, weapon ownership, the water meter, the HUD and the mod API take every registered one; his pack `dun/mainchara/c07d.chr` and portrait `c07d_face.png` load in his own slot; no registered character is ever written to a save (see below). | Yes |
| 4 | **Staffs**: six staff models, the Ruby-style attack for him, spit visuals, the line in §4, icons | Mod + small engine (icon atlas entries) |
| 5 | **Motions**: `opar_moves.py`, his proportions, his shadow model, the blink | Mod + tools |
| 6 | **Kit and Opar Form**: his moves, the special trigger, the monster model in the player's slot with its motions mapped to idle, move and attack, the timers and the mist | Yes (special trigger, monster swap) |
| 7 | **The Gauntlet**: joining, Signature sky, companion, character blocks, balance, voice and sounds | Mod |

**Risks.** The extra-character slots touch the most code and are done first, with their own tests. The monster form needs the
monster's motion table driven by the player controller; it is built behind a mod setting until it passes its gate.
The reworked model (about 15,000 triangles) takes 207,891 quadwords of the character model arena. The port carves
that arena at four times the PS2's 210,000 (`kArenaHeadroom`); phase 3 made the weapon and effect models take what
is left of the carved arena rather than of the PS2 figure, which is what stopped him loading. A companion of him
would need a second copy; that is phase 7's to measure.

### How the extra playable characters are built (phase 3)

The user asked for room for more heroes than Opar, so the slot is a registry rather than one hard-coded seventh.

- **`SAVE_CHARA_COUNT` = 6, `CHARA_MAX` = 16** (`itemdata.hpp`); `CharaCount()` is the six plus every registered one.
  A mod registers a character with `characters.register_playable({id, name, pack, portrait?, fights_as?, hp?,
  defense?})` (`playable_chara.hpp`); he takes the next index from 6 and keeps it while the game runs. Opar is the
  Gauntlet's, index 6.
- The save's per-character arrays are `CharaSlots<T, Field>` (`userstatus.hpp`): laid out as the game's `T[6]`, so the
  save's size and every offset hold (`sizeof` asserts), with indexes 6-15 going to storage outside the save. Writing
  a save image clamps `party_size` to 6 and `cur_chara` to Toan, so no save ever counts a registered character.
- **`CombatChara(chara)`** is a registered character's `fights_as`: the character whose action, weapons, voice,
  motions, weapon models, menu poses and atlas face he borrows. The game's per-character tables stay six long and are
  read through it. Every native `cur_chara == CHARA_X` test asks it.
- **`CharaSlotsInPlay(party_size)`**: the switch wheel and the menus' turntables have a place for each registered
  character the party reaches (a party holds the first `party_size`), so a story game keeps its six.
- Names come from the registry (letters only, up to 10), printed by their own text codes (-0x507 down) and system
  message lines (2000 + index); portraits are the PNGs they name (128 x 128).
- **The Gauntlet**: the **Opar** setting (off by default) puts him in the roster of new runs, as a starting character
  and a draft, if his registration took; a run keeps the roster it started with. The run asks `session.start` for a
  party of seven. Toan's weapons are his (`weapons.give` with `character = "opar"`); he has no Signature sky or
  Legendary yet (phase 7).

---

## 8. Story mode (planned 2026-10-30)

The user wants Opar in the main game too, early on: he joins with Xiao. In the story, Xiao is a cat found in the
Divine Beast Cave who goes into an Atla like a house piece. Placed in Toan's house, she gets a scene there
(`gedit/e01/in/i01h01/event.stb`, the function at code+0x86b8): the cat (`e04c04cat.chr`) with the `appear` and `kira5`
effects, his mother's lines (message 20402 and around it), the cat turning into the girl, then `SSET_PARTY_NUM(2)`,
`SITEM_GET(22)` and `SEQUIP_DEFAULT_WEAPON(1)`. Baby Opar goes through the same: his own Atla, placed in the same house,
the same scene with her mother's lines rewritten for him, and he joins with the same item. He is the monster `e104a`
shrunk to the cat's size. He gets no leg hug or other motions of Xiao's after the change.

What the Gauntlet built carries over: his model, motions, staffs, moves, Opar Form, voice, menus. What the story needs
on top of it:

| Phase | Work | Engine? |
|---|---|---|
| S1 | **Opar as his own mod** (`moonmod.opar`): his character, pack, voice, staffs, moves, form and menu art move out of the Gauntlet into one mod both use. The Gauntlet declares it as a dependency, so he is registered once. | Mod |
| S2 | **Registered characters in story saves.** Today none is ever written to a save, and a party is the first `party_size` characters. Story mode needs: a joined set apart from `party_size` (he joins at 2 without being 7th), and his slots (HP, water, weapons, equipped, status) kept in a file beside each save. The save itself stays a retail one, so a save still loads without the mod. | Yes |
| S3 | **The join.** His Atla in the Divine Beast Cave beside the cat's; the house scene run with him in it (`native.event.run` over the house program, or an engine hook in that function): the shrunk `e104a` with the same effects, her lines rewritten (message overrides), then he joins alongside Xiao with the item and his Driftwood Staff. | Mostly mod; a small engine hook if the scene can't be wrapped |
| S4 | **His story weapons.** The six staffs found and bought like the others' weapons: shop lists, chests, build-up chains from one staff to the next, the Tidecaller as his ultimate. His moves and Opar Form on in story dungeons. *Built: kit and Opar Form in story dungeons; all six staffs registered and chained; Reed, Coral, Bog Oak and Moonpearl in shops 1, 8, 10, and in chests once he has joined (Reed from the cave's 8th floor, then one per dungeon, 15% of chest weapons).* | Mod + data tables |
| S5 | **The rest of the story with him in it.** Scenes that load the whole party (the ending, the Dark Genie) skip him safely; the switch ring, status and item menus with seven; a story save and load round trip; the save with the mod removed. | Checks, fixes as found |

**Settled (the user, 2026-10-30).** Both join together at the house scene: the same scene, Xiao and baby Opar both
join, both get the item.

**Order.** S2 first: it is the foundation and the riskiest (the save). S1 touches the Gauntlet's `main.lua`, so it
waits on the Gauntlet session.

**S2 built (2026-10-30).**
- Engine:
  - joined registered characters (`CharaJoined`, `InParty`, `PartyCount`, `NextPartyMember`, `CharaSlotsInPlay(status)`) across the menus, the change ring, the item menu's character tabs, the status loops and the API;
  - `party.join` / `party.leave`;
  - `characters.json` beside each save (`chara_extras_save.cpp`);
  - a weapon given to empty hands is equipped.
- Tested: the roster tests (12, three new) and in game with a test mod. In a fresh story game he joins Toan, takes the change ring and leads with his weapon.
- Not yet seen in game: a story save and load (the file round trip is unit-tested).

**S3 findings (2026-10-30).**
- **Xiao in the story:**
  - She is element 54 of Norune: Atla 94, on the Divine Beast Cave's 8th floor.
  - The element belongs to Toan's house (part 0).
  - The house's interior script (`gedit/e01/in/i01h01/event.stb`) stands the cat in as villager slot 1 (`LOAD_IN_VILLAGER(1, -1, 'c04pcat', ...)`), once her element is in and game flag 18 is unset.
  - Talking to her runs program 11. Using item 237 on her sets flag 18 and plays the scene (func code+0x86b8), which ends `SSET_PARTY_NUM(2)`, `SITEM_GET(22)`, `SEQUIP_DEFAULT_WEAPON(1)`.
- **No free element slot:** Toan's house has six element slots and all six are used (`taru`, `entotu`, `koya`, 52, 40, 54). A seventh needs the element tables, the editor and a store outside the save (the save keeps six per plot).
- **What exists and what is missing:**
  - The mod API has `text.set` (her mother's lines) and `native.event.run` (a whole program replaced).
  - It has no mod Atla in a dungeon, no villager inside a house, and no way to add a character to a native scene.
  - The scene needs either a patched copy of the house's script (`resources.override`, with an `.stb` patcher beside `tools/stb/stbdis.py`) or engine hooks in it.

**S3 built, option A (the user's choice, 2026-10-30): his own sphere on the cat's floor; he moves in with the cat.**
- **Engine:**
  - mod Atla spheres (`georama.atla_spawn`, `game.georama.atla_collected`; `mod_atla.cpp`). Toan opens them with the game's pickup, and it says "'Baby Opar' acquired." They hold nothing of the game's.
  - A floor's sphere table raised from 8 to 16.
- **Tools:** `tools/stb/stbpatch.py` appends code, strings and programs to a compiled script and hooks it. It retargets a CALL, or turns an EXT followed by a constant PUSH into a CALL that does the EXT and more; calls still run while a scene is skipped.
- **Packs:** `art/opar/make_baby.py` builds `c07baby.chr` (house), `e04c07baby.chr` (scene) and `e04c07opar.chr` (grown, scene).
- **The house:** `art/opar/story/patch_house.py` patches Toan's house:
  - baby Opar beside the cat (villager slot 6, scale 0.15);
  - in her scene, his two loaded after hers; when the cat turns into Xiao, he turns into Opar;
  - game flag 7002 set as the party is made two;
  - program 11 wrapped for his late, short join.
- **The mod `moonmod.opar`:**
  - the sphere on the cave's 8th floor until found (story flag 7001);
  - the mother's two lines for two (205, 20402);
  - on 7002 he joins with his Driftwood Staff;
  - nothing in a Gauntlet (sandbox) run.
- **Checked in game:** the sphere is put on the floor, picked up, its name shown, its mod told; the story mod puts it on the floor.
- **Not yet seen in game:** the house and its scene. They need a story save with the cat's element in Toan's house. The positions, scale and grown Opar's load are first guesses until then.

**S3 checked in game (2026-10-30), with a developer jump.**
- **The jump:** `darkcloud --jump house:<interior>[@<event>]` (engine: `GameSetJump`, `SetDevHouseJump`) starts in the house's town and goes in through `GotoInterior`, with the house's plot marked complete.
- **Launcher:** `E:\Gauntlet-build\play\Opar House Test.bat` makes a fresh test save with `moonmod.opar` and `tools/tests/story/moonmod.opar-housetest` (flag 7001 set, item 237 given) and starts `--jump house:i01h01@150` (program 150, the cat's scene).
- **Seen in game:**
  - baby Opar on the bed beside the cat, at her size;
  - Opar grown appears as she turns into Xiao, standing on the floor by the bed's foot (36.5, 37.6, -16), clear of the bed (the user saw him in it where he first stood);
  - the line "Xiao and Opar have become allies.";
  - after the scene the party is Toan, Xiao and Opar (flag 7002 set by the house, the join by the mod).
- **Fixed on the way:**
  - the scene positions are (x, height, z), so grown Opar first floated;
  - a town character model may now be up to 16 MiB (grown Opar's pack is 4.1 MB; it was refused at the 2 MiB monster limit).
- **Not yet seen:**
  - the scene reached by using item 237 at the cat (the test starts it directly);
  - his late join;
  - his sphere on the 8th floor (seen on the 1st with a test setting);
  - a story save and load with him.
