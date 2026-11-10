# Items, gear, weapons and shops

Part of the [MoonFactory API reference](../API.md). Item and weapon definitions, registering new ones, the inventory,
charm slots and gear, weapon growth, shops and inventions.

Every operation named here is listed with its permission and per-game support in the [operation index](OPERATIONS.md).

**In this chapter**

- [Built-in items, quick slots and charm slots (Chronicle)](#built-in-items-quick-slots-and-charm-slots-chronicle)
- [Data-only items (Chronicle)](#data-only-items-chronicle)
- [Data-only items (Chronicle Two)](#data-only-items-chronicle-two)
- [Gear (Chronicle)](#gear-chronicle)
- [Weapon definitions (Chronicle)](#weapon-definitions-chronicle)
- [Weapon definitions, equip and upgrade (Chronicle Two)](#weapon-definitions-equip-and-upgrade-chronicle-two)
- [Data-only weapons (Chronicle Two)](#data-only-weapons-chronicle-two)
- [Weapons and items with their own model and icon (Chronicle)](#weapons-and-items-with-their-own-model-and-icon-chronicle)
- [Weapon styles (`weapons.style_set`, Chronicle)](#weapon-styles-weaponsstyle_set-chronicle)
- [Weapon ABS, attachments and build-up](#weapon-abs-attachments-and-build-up)
- [Shops (`shops.*`)](#shops-shops)
- [Inventions (Chronicle Two)](#inventions-chronicle-two)

## Built-in items, quick slots and charm slots (Chronicle)

```lua
for _, item in ipairs(game.items.list()) do
  print(item.id, item.item_no, item.kind, item.message_id)
end

local bread = assert(game.items.get("chronicle:item:148"))
print(bread.use_flags, bread.initial_volume, bread.stack_kind)

for _, slot in ipairs(game.items.quick_slots()) do
  print(slot.slot, slot.id, slot.count)
end
assert(game.items.quick_slot_select({slot = 2})) -- selects only
assert(game.items.quick_slot_use({slot = 2})) -- requests a normal native action-button use
```

Chronicle reads built-in definitions from its native common-item and item tables. The stable ID is
`chronicle:item:<item_no>`; results include the native message and icon indices, sort key, use and kind flags, initial
volume, and stacking behavior. `items.give` and `items.remove` use Chronicle's native dungeon inventory routines, accept
counts from 1 to 999, and report the actual quantity changed. They require an active save and respect the native
item-pack capacity.

Chronicle's `items.quick_slots()` returns the three native quick-item assignments as `{slot, item_no, id, count}`
records; empty slots have null `item_no`/`id` and a zero count. `items.quick_slot_select({slot = 1..3})` changes the
native selected slot only during active dungeon play. `items.quick_slot_use({slot = 1..3})` selects the slot and queues
the ordinary native action-button path briefly; item animations, consumption, and effects therefore remain controlled by
the game.

`items.use` accepts built-in HP and water consumables and the four native single-status cures, plus registered mod
HP/water items and status remedies. It defaults to the active character and accepts `character = "active"` or a joined
playable character id such as `"xiao"`; the target must be alive and eligible for that effect. It delegates to
Chronicle's `ItemUseFunc` and consumes exactly one item after the native routine accepts it.

Chronicle's **charm slots** are each character's own slots on the item page, beside their weapon and shield on the
character panel, that hold only the four amulets (Anti-Freeze, Anti-Curse, Anti-Goo, Antidote). An amulet in a charm
slot is out of the bag and takes none of its room. When a hit rolls an ailment, an amulet in the active character's
charm slots guards against it before the quick slots are looked at, spending a use as the game's own amulets do and
breaking with the last. On the page, Right from the shield reaches them (an empty one shows an amulet blacked out),
Cross puts the held amulet in (or picks it up), and Square sends it back to the bag. `items.charm_slots_set({count =
0..4, feather = optional boolean})` (`game.write`) opens that many amulet slots for every character, and with `feather =
true` one more after them that takes only Dran's Feather (an amulet slot refuses the Feather and the Feather's slot
refuses amulets); none, the default, is the game's own page. `items.charm_slots()` returns `{open, feather, characters =
{toan = {{slot, kind, item_no, id, uses}}, ...}}` (`kind` is `"amulet"` or `"feather"`, `slot` the position on the page)
with every character's shown slots: those open, plus any further one still holding an amulet, so an amulet is never out
of reach after its mod closes the slots. They are not in the save image: the engine keeps them beside it as
`charms.json` in the save slot's folder, by character id (a character no mod registers now keeps theirs), written and
read with the save, so they come back with it whether or not the mod is loaded. In a dungeon the active character's
charms show on the HUD left of the gate-key plate (before any `render.hud_icon_set` icons), each with its uses left in
the corner, as the item page's slots show them. A worn amulet sells for less: its price times the uses left over its
full uses, and nothing once it is worn below half of them. Dran's Feather, in its own slot, lightens a `dodge_run` run
(half the drain), spending a use each tick of running, and shows its time left in seconds; it sells for its price
whatever is left. A Feather a file keeps in an amulet slot moves to its own on load.

## Data-only items (Chronicle)

```lua
local item = assert(game.items.register({
  id = "starlight-tonic",
  name = "Starlight Tonic",
  kind = "consumable",
  template_item = 148, -- inherits Chronicle Bread's native presentation
  assets = {},
  effect = { kind = "heal", amount = 25 }
}))

local grant = assert(game.items.give({ id = item.id, count = 2 }))
local use = assert(game.items.use({ id = item.id }))
assert(use.healing == 25)
```

Chronicle supports data-only HP-healing, water-restoring, single-status, and combined status-cure consumables copied
from a built-in item template. Definitions use no asset overrides; they inherit the template's native icon and message
presentation while `items.get/list` return the mod's own stable ID and name. A status remedy can use `effect = {kind =
"cure_status", status = "poison"}`; supported statuses are `freeze`, `poison`, `curse`, and `goo`. A `cure_all` effect
clears those four supported ailments in one native item use.

Both cure forms replace the template effect flags and call Chronicle's native `ItemUseFunc`; the item is consumed only
when the active living character has at least one ailment it clears. Chronicle preserves its original 11 saved slot
assignments first, then searches the native consumable range and allocates only rows whose definitions are unused.

The retail headless smoke registers 12 simultaneous data-only items and confirms the twelfth uses native row 142; the
total capacity depends on the unused rows in the game's fixed table. Assignments are stored at
`<save>/moonmod/game-content/chronicle-item-slots.json` and kept as tombstones if a mod is removed, so a saved inventory
number is never reassigned to a different item. The inherited localized display name remains a Chronicle-specific
constraint.

`items.give`, `items.remove`, and `items.use` accept the registered stable ID. Other effect types, per-item stack caps,
and asset overrides are not implemented.

## Data-only items (Chronicle Two)

```lua
local item = assert(game.items.register({
  id = "starlight-tonic", -- automatically namespaced to this mod
  name = "Starlight Tonic",
  kind = "consumable",
  template_item = 274, -- an existing usable item number in ChronicleTwo
  max_count = 20,
  max_stack = 5,
  effect = { kind = "heal", amount = 25 }
}))

-- After the game's item tables have loaded:
local grant = assert(game.items.give({ id = item.id, count = 2 }))
local use = assert(game.items.use({ id = item.id, target = "max" }))
local removed = assert(game.items.remove({ id = item.id, count = 1 }))
assert(removed.removed == 1)
```

Registration can happen during mod startup, before native item tables load; the returned record then has `status =
"pending"`. ChronicleTwo materializes those definitions after its item data and localized item messages load. A
definition may omit `assets` or provide an empty table. Non-empty asset overrides are rejected by this first adapter.
Only the mod namespace can be used in an explicitly qualified mod item ID. The current native adapter has a 32-item
limit per running game session and supports only consumables copied from a usable vanilla item.

`items.give` and `items.remove` operate on registered item IDs and report the actual quantities accepted or removed.
`items.use` invokes ChronicleTwo's native use rules for an owned item and currently supports Max or Monica as the
target. Arbitrary owner-provided Lua effect callbacks remain future API work.

The optional `effect` override supports `heal` with an integer `amount`, `power` to apply Chronicle Two's native timed
power status, `cure_status` with one of `poison`, `slow`, `stop`, `curse`, `stone`, or `dry`, and `cure_all` for all six
supported ailments. Each override replaces the template's native effect flags while retaining its native action, target,
icon, model, and item-family behavior.

These effects run through Chronicle Two's own item-use routine; the result includes before/after status flags, whether
they changed, and the native power-status timer in frames. Unlisted effects such as repair, weapon absorption, stat
growth, damage, and Lua callbacks remain unsupported. Chronicle supports native freeze, poison, curse, and goo
single-status cures and a combined `cure_all` through the same data-only registration and native item-use path; the
`power` effect is currently Chronicle Two only.

`items.list` and `items.get` include loaded built-in non-weapon definitions plus registered mod items. Built-in IDs use
`chronicle-two:item:<item_no>`; mod item IDs use the registering mod's namespace. `items.give` and `items.remove` accept
those IDs and the stable IDs returned by `weapons.list/get/register`, so registered weapons can enter and leave the
inventory through the same native inventory path. They report the actual amount accepted or removed. The inventory API
does not expose unregistered content by a guessed number; the ID must resolve through loaded game data.

## Gear (Chronicle)

```lua
local piece = assert(game.items.gear_give({kind = "boots", name = "Swift Boots", rarity = 1, value = 180,
  effects = {run_cost = 16, guard = {goo = 30}}}))
game.items.gear_equip({uid = piece.uid})              -- on the active character; or character = "xiao"
local gear = game.items.gear()                        -- {pieces, bag, bag_max, bag_slots, worn = {toan = {slots, effects}}}
game.items.gear_unequip({kind = "boots"})             -- back into the bag
game.items.gear_remove({uid = piece.uid, sell = true}) -- {uid, money}
game.items.gear_page_set({icons = {hat = "gear_hat", tunic = "gear_tunic", gloves = "gear_gloves", boots = "gear_boots"},
  parts = {toan = {hat = {draw = {"boushi"}, turn = 40, bare = {"boushi", "cloth1"}},
                   boots = {draw = {"skin", "l_f", "r_f"}, fit = {"l_f", "footl", "eff7"}, turn = 70, tilt = 15}}}})
```

Each character wears up to five **gear** pieces, one of each kind: `hat`, `tunic`, `gloves`, `boots` and `pouch`. A mod
makes each piece with `items.gear_give({kind, name, rarity?, value?, icon?, color?, effects?})` (`game.write`): `name`
1-32 bytes, `rarity` 0 to 4 (common, uncommon, rare, epic, legendary: the Gauntlet's five, named and coloured so in the
item page's help box; a gear.json from before version 2 had four, and its 3, unique, loads as legendary), `value` the
Gilda it sells for (0 to 65535), and `effects` any of `guard` (`{freeze, poison, curse, goo = percent}`, 0 to 90 each),
`stamina` (gauge a second, 0 to 120), `lightness` (percent off a swing's cost, 0 to 50), `defence` (0 to 99), `run_cost`
(percent off what a `dodge_run` drains, 0 to 75), `poise` (points of hits taken without a stagger, 0 to 8) and `bag`
(item bag slots, 0 to 50). `icon` is the stem of an `icons/<stem>.png` a mod provides (as `items.register` takes one;
without it the piece shows its kind's icon) and `color` `{r, g, b}` (0 to 255 each) tints it, so one grey icon can make
a red pair of boots and a blue one. It goes into the gear bag, which holds 99 pieces besides those worn, and the result
is the piece: `{uid, kind, rarity, name, value, effects, worn_by, icon, color}`; a full bag fails. `uid` numbers the
piece for good (never reused in that save). Pieces are not the game's items and take no room in the item bag.

`items.gear_equip({uid, character?})` puts a piece on (`character` an id or `"active"`, the default), taking it off
whoever wore it; what was in that slot goes to the bag. `items.gear_unequip({kind, character?})` takes one off into
the bag (failing when the bag is full or nothing is worn there), and `items.gear_remove({uid, sell?})` takes a piece
away, worn or not, with `sell = true` adding its value to the wallet (up to the wallet's 65535). `items.gear()`
(`game.read`) returns every piece, the bag's count and size, and for each character the uid in each slot (or nil) and
`effects`, what their worn pieces do together.

The engine reads the active character's worn effects where the game decides each thing, added up across the pieces
and capped: a hit that rolls an ailment first rolls the `guard` chance against it (90% at most) and, if that holds,
nothing happens and no amulet is spent; `defence` is taken off each hit with the character's own; `stamina` is added
to the refill (`player.tuning_set` `stamina`, or the game's) on any frame it isn't stopped, halved by Goo (120 at
most); `lightness` scales every swing's cost (half at most) on top of the tuning's `lightness`; `run_cost` scales the
run's drain (75% off at most) on top of Dran's Feather; `poise` (8 at most) takes a landed light hit for 1 point and a
heavy one for 2 with no stagger: the damage and the hurt sound, but no flinch, knockdown or recoil, and the swing or
dodge under way goes on. A hit past what is left staggers as usual and leaves poise whole for the next; poise is whole
again 2 seconds (120 frames) after the last hit. A trap, a broken guard or a hit that would empty the life bar always
staggers. `bag` grows the game's item bag (the one its Pockets grow) by the largest any character wears (50 at most;
one bag for the party), never past the game's own 100. Taken off, the bag shrinks as far as its items let: items in
the slots that go move into empty ones, and while it is too full it stays larger, shrinking as it empties. The engine
remembers what it added (`items.gear()` `bag_slots`), so the size the save's Pockets gave it is left alone; the item
page and the gear calls bring the bag in line. Gear is kept beside the save as `gear.json`, read and written
with it; a piece worn by a character no mod registers now stays theirs.

`items.gear_page_set({icons = {hat, tunic, gloves, boots, pouch?}})` (`game.write`) opens the gear page on the game's
item page, each `icons` entry a stem as `icon` takes (the first four are needed; each kind's empty slot shows its icon
blacked out). Name `pouch` too and the page has a pouch slot, at the character's hip in the outer column; leave it out
and the page has four slots, as before. The personal board gets a fourth tab, **Equipment**, holding the bag: Cross
picks a piece up and puts it back, the trash can throws it away, and the help box names the piece under the cursor with
its rarity, price and effects. The character card gives way to the **hero page**, a panel in the help windows' frame:
the character alone and larger, down his left side his charm slots and then his weapon (its attack in the corner, its
wear up its edge) and shield, any charm slots past the second (and the pouch) in a column further out, the other gear
slots down his right side and his HP and water across his feet. The help box at the bottom left says what Cross and
Square do on the slot under the cursor. Cross with a piece in hand on its kind's slot puts it on, the piece it replaces
coming up into the hand; Cross on a worn piece takes it into the hand (past a full bag, until it is put down) and Square
takes it off to the bag. One of the character's weapons picked up from the Weapons tab and dropped on the hand is
equipped, with the weapon menu's checks (a curse, a no-weapon-change zone, a character out of the party); an Osmond or
Ruby in play keeps theirs until the weapon menu, which reloads their weapon's effects. The mouse carries pieces as it
does items: press on a cell or slot, let go on another. `items.gear_page_set({})` closes it all, and `items.gear()`
reports `page`.

While the page is open, a native item shop shows the Equipment tab on the player's side too: Triangle on a piece sells
it for its `value` (the shop's usual "sell it?" question; a wallet at 65535 refuses). Cross can't take a piece onto
the counter. `items.gear_stock_set({shop, goods})` (`game.write`) stocks a shop (its number, as `shops.*` uses: 0 to
17 for the game's own) with up to 10 pieces, each as `gear_give` takes it plus `price` (0 to 65535 gilda; its `value`
when left out). They lie in the shop's empty cells after its own goods, drawn as in the bag, and the help box names the
one under the cursor with its price. Triangle buys one into the bag (refused past a full bag or a thin wallet); Cross
can't drag one into a deal. A bought piece is gone from that shop until the mod stocks it again, and `{shop, goods =
{}}` takes the shop's gear away. Stock is kept for the session only, not in the save; with the page closed no shop
shows its gear.

`parts` (optional) shows each hero's own clothes in place of the icons: for a character id, each kind names frames of
that character's menu model, either as a list (1 to 8 names, up to 31 bytes each; a name matches a frame's whole name or
the part before its `__` flags) or as `{draw = names, fit = names?, bare = names?, below = names?, turn = degrees?, tilt
= degrees?}`. The slot draws only the `draw` frames, grown and centred until the `fit` frames (all of `draw` when left
out) fill it, the model turned `turn` degrees (-180 to 180, left positive) and held there, and leant back `tilt` degrees
(-90 to 90, forwards when negative) so a part the menu camera sees from above, such as a boot, shows from the side. A
piece's `color` fills the ground behind its part and warms the light a little, so the part keeps its own look; an empty
slot draws its parts dark, except a kind with `bare` frames: the hero isn't wearing them, so its empty slot has the
kind's icon. This covers the hero page's slots, the Equipment tab's cells and the piece in hand, for pieces whose icon
is their kind's own; a piece with an icon of its own, a kind with no parts and a hero with none keep the icon, as does
the page while the model is still loading. The parts are the character's whose page is shown. Cloth the model simulates
is drawn in a slot as it hangs at rest. `bare` names frames the character's models leave out while nothing is worn in
that slot, on the hero page and in the world alike (cloth hanging from one of them is left out with it): his hat, with
no hat on. The hero in the dungeon and on the item page are known by which model they are; elsewhere (Toan in town) a
model is the character's when its root's name starts as the character's pack does (`c01`). A frame that is any model's
root, or a character with none named, is drawn as ever, and nothing is left out while the page is closed. `below` cuts
the slot off a third of the way down the named frames' box (at the joint itself for a bone with no mesh of its own, such
as an ankle), and fits the slot to the `draw` frames' vertices under that cut instead of `fit`: a part of a bigger mesh
alone, as his shoes are part of his body (`draw = {"skin"}, below = {"l_f"}`, the shoes under his ankle wraps). Toan's
are `boushi` (hat) with `cloth1` (its tail, cloth), `cloth2` and `cloth3` (his vest's front and back, cloth) with
`beruto` (the belt), `l_g` with `l_hand` (the glove's cuff and the hand), `l_f` (his ankle wrap) and `kaban` (the
satchel at his hip); `r_g`, `r_hand` and `r_f` are the other side's, and `skin` is his body, his shoes and shirt with
it. With no hat his hair is open at the crown where the hat sat, which a camera from above can catch. The others' menu
models (`commenu/dungeon/c0Nmodel.pak`): Xiao `l_hand` (her paw), `l_ude` (arm wrap), `l_asi` (leg wrap), `suzu` (bell),
`skin` (her dress and shoes); Goro `mant` (his bear mantle, cloth), `faces2`, `skin` (the hood is part of it); Ruby
`cube37` (tiara), `body5` (left hand and cuff), `cube40`/`cube60` (slipper toes), `l_foot`, `skin`; Ungaga `cap`
(feathered cap), `cloth1`/`cloth2` (sash tails, cloth), `l_udewa_2` with `r_hand4` (a bracer and its hand), `kubikaazri`
(necklace), `skin`; Osmond `face` (goggles), `l_hand4` (glove), `bag`, `backpack` (his jet pack), `l_foot`, `skin`.

## Weapon definitions (Chronicle)

```lua
for _, weapon in ipairs(game.weapons.list()) do
  print(weapon.id, weapon.owner, weapon.stats.attack, weapon.socket_count)
end

local dagger = assert(game.weapons.get("chronicle:weapon:258"))
for _, instance in ipairs(dagger.instances) do
  print(instance.character, instance.level, instance.equipped)
end

local blade = assert(game.weapons.register({
  id = "moonblade",
  name = "Moonblade",
  template_weapon = "chronicle:weapon:258",
  owner = "toan",
  stats = {attack = 37, durability = 81},
  stat_caps = {attack = 99, magic = 40},
  assets = {}
}))
local grant = assert(game.weapons.give({id = blade.id}))
assert(grant.added and grant.native_item_no == blade.native_item_no)
```

Chronicle lists its 120 retail weapons and registered definitions. `weapons.get()` accepts a
`chronicle:weapon:<item_no>` ID for retail weapons, a mod-owned stable ID, native item number, or selector object.
Results include base stats, caps, elements, monster effectiveness, socket count, experience/build-up metadata, and
matching owned instances with equipped state. Each owned instance reports maximum `stats.durability`, live fractional
`stats.durability_current`, per-instance `elements`, `vs_monster`, and `flags`. The ownership fields are `nil` without
an active save.

Registration allocates one of 32 appended native slots (377-408) and persists the stable ID to
`moonmod/game-content/chronicle-weapon-slots.json`, so the same mod keeps the same native item number across launches. A
definition inherits its template's owner, icon, name message, elements, sockets, experience, and build-up data; it may
set `owner`, `stats.attack`, `stats.durability`, `stat_caps.attack`, and `stat_caps.magic`.

`owner` may be a registered playable character (`"opar"`): the weapon then belongs to the character he fights as
(`owner` reads that one, so the combat code treats it as theirs) and sits in his own row of the weapon page, chests and
pickups put it there, and only he can be given it; `weapons.get` reports him as `holder`. `assets` must be empty. The
API's `name` is available to Lua, but Chronicle's inventory menus still display the inherited native localized name.

`weapons.give({id, character?})` adds one copy through the game's inventory path and assigns it to the compatible
character, or to `character` (a joined playable id) when given; a weapon fits its owner, and a registered playable
character the weapons of the character he fights as (`fights_as`). `weapons.equip({id, character?, slot?})` equips one
owned compatible weapon on a joined character.

Chronicle changes the loadout in an active Georama town or dungeon; in a dungeon, equipping the active character's
weapon reloads the character and weapon models through the native character-switch routine, and is refused during an
attack or other locked action. `weapons.remove({id, character?, slot?})` deletes one owned instance that is not equipped
(Chronicle only). The character defaults to the active member; `slot` is required when the character owns multiple
copies. Repeating the current selection succeeds with `changed = false`.

`weapons.stats_set({id, character?, slot?, attack?, endurance?, speed?, magic?, durability?, elem?, vs_monster?,
flags?})` is Chronicle-only and updates exactly one owned native weapon instance. Scalar stats accept integers from 0 to
32767, `elem` takes five values and `vs_monster` takes ten values from 0 to 127, and flags accept a 16-bit value.
Specify both `character` and `slot` when the weapon has multiple copies. A durability-maximum update preserves the
current durability fraction; element and effectiveness writes update the native saved weapon data.

`weapons.durability_set({id, durability, character?, slot?})` sets current durability from zero through that instance's
native maximum without changing the maximum. New model/animation identities are not part of this registration path yet.

`weapons.stat_label_set({attack?, endurance?, speed?, magic?})` (`game.write`, Chronicle only) shows a mod's own image
as a stat's label on the weapon menu's cards, in place of the game's two letters (At, Ed, Sp, Mp): each value is a stem
as `items.gear_give`'s `icon` takes (icons/<stem>.png, put there with `resources.override`). The card under each
weapon draws it in the label's 16x12 cell. On the Status tab, whose four labels are painted into it overlapping one
another, any label set wipes the whole column to plain stone and lays all four again one size, each in a 26x15 box
centred on its bar: the mod's image, or the game's own label from the card for a stat left out (so set all four for
one look). Draw a label at 52x30 for a crisp one (it is loaded as 32x32 and stretched back). `{}` gives the game's
labels back. It changes only the label, not the stat. Vigil sets all four, Speed reading "Lt" under its Lightness rule.

`weapons.definition_set({id, ...fields})` is Chronicle-only and changes the live base definition of one built-in weapon
so future native drops and purchases inherit the edited values. It supports attack, endurance, speed, magic, durability,
owner, six socket types and socket count, five element values, ten monster-effectiveness values, ABS fields, flags, both
build-up masks, attack/magic caps, and chain position. Another mod cannot override a weapon definition already owned by
a different mod.

Chronicle restores the complete original definition when the owner unloads. Existing weapons in saves keep their saved
stats, matching the legacy Expanded Data mod. This operation does not alter localized names, model identities, shop
inventories, or daily rotations; Chronicle Two does not expose this operation.

## Weapon definitions, equip and upgrade (Chronicle Two)

```lua
for _, weapon in ipairs(game.weapons.list()) do
  print(weapon.id, weapon.name, weapon.stats.attack)
end

local blade = assert(game.weapons.get({id = "chronicle-two:weapon:80"}))
if blade.state then
  print(blade.state.level, blade.state.durability.current)
end
```

These read-only operations expose loaded native weapon definitions, including attack and attribute values, caps, special
flags, build-up requirements, and the native model key. `weapons.get` also reports the number owned and the first
matching owned weapon's live level, durability, absorption, stats, and custom name when an active save contains one. A
selector may use the returned stable id or a native item number. Chronicle exposes the same list/get operations over its
compiled weapon table and reports every matching owned instance; its definition shape uses Chronicle's native stat and
buildup fields.

```lua
local equip = assert(game.weapons.equip({id = blade.id, character = "max"}))
assert(equip.equipped)
```

`weapons.equip` routes through ChronicleTwo's native inventory/equipment rules. The weapon must already be in the
inventory, must be compatible with Max or Monica, and cannot already be equipped. If `character` is omitted, the active
character is used and must be Max or Monica.

```lua
local result = assert(game.weapons.upgrade({id = blade.id}))
if result.upgraded then
  print(result.previous_level, "->", result.level)
end
```

Both games require an owned weapon whose native experience has reached its current level-up threshold. A weapon that is
not ready, or is already level 99, returns a successful result with `upgraded = false` and `changed = false`. Chronicle
applies its native weapon-stat calculation, durability roll, level cap, and attachment conversion while retaining
cumulative experience; if the same weapon is owned more than once, pass both `character` and that character's `slot` to
select one instance.

ChronicleTwo applies the game's native durability roll, stat and fusion-point gains, character-favored element bonus,
and absorption reset. Successful changes queue `game.weapon.upgraded` for the next runtime pump.

## Data-only weapons (Chronicle Two)

```lua
local blade = assert(game.weapons.register({
  id = "moonblade", -- automatically namespaced to this mod
  name = "Moonblade",
  template_weapon = 80, -- an existing ChronicleTwo weapon item number
  stats = {attack = 18, durability = 125, attributes = {3, 4, 5, 6, 7, 8, 9, 10}},
  stat_caps = {attack = 120, durability = 500, attributes = {50, 51, 52, 53, 54, 55, 56, 57}},
  durability_capacity = 31,
  level_up_exp = 40,
  assets = {}
}))

-- After native weapon tables load, the same stable ID resolves through weapons.get/list.
local definition = assert(game.weapons.get(blade.id))
local grant = assert(game.weapons.give({id = blade.id}))
```

The definition inherits its model, icon, weapon type, attack behavior, special flags, and build-up path from the
template. Mods may override attack/durability values and caps, the eight elemental/stat attributes and caps, durability
capacity, level-up experience, and inventory limits. New texture/model/audio files are not required or accepted by this
adapter. Registration queues during mod startup and becomes native after the game's weapon tables load; before then,
`weapons.get` returns `phase_violation`. ChronicleTwo accepts up to 32 mod weapons per session; Chronicle allocates up
to 32 persistent native slots.

## Weapons and items with their own model and icon (Chronicle)

On Chronicle, registered content can bring its own files. Every file is a `game.resources.override` the mod owns (1 byte
to 2 MiB), registered before the content that names it.

```lua
game.resources.override({path = "resources/annexmdl.chr", game_path = "commenu/weapon/annexmdl.chr"})
game.resources.override({path = "resources/annexicon.png", game_path = "icons/annexicon.png"})
local blade = assert(game.weapons.register({
  id = "annex", name = "Annex Blade", template_weapon = 262, owner = "toan",
  model = "annexmdl",   -- commenu/weapon/annexmdl.chr
  icon = "annexicon",   -- icons/annexicon.png
}))
```

- `model` names `commenu/weapon/<stem>.chr`. The game reads the template weapon's `.cfg` from inside it, so the file
  must hold a `.cfg` with the template's name (for template 262, Toan's sixth weapon, `c01w05.cfg`). Without `model`
  the weapon draws its template's model. Native names (`cNNwNN`) are refused.
- `icon` names `icons/<stem>.png`, any size, drawn into the 32x32 menu cell. `items.register` takes `icon` too.
- `description` (a string, or up to 4 lines of 1-64 bytes) is what the weapon menu's card says of it. A registered
  weapon a mod hasn't styled (`weapons.style_set`) goes by its own `name` in the menus and shows its `description` on
  the card, in place of its template's name and text; a styled one shows its style.
- `menu_scale` (0.1 to 4, default 1) is how big the weapon menu draws the model, against its holder's own weapons:
  a model made bigger than the template's (Opar's staffs, 1.45 times a sword) is shrunk to fit the menu's frame.
  In the hand it keeps its own size. `weapons.get()` reports it when it isn't 1.
- `items.icon_set({id, icon})` (`content.register`) gives a built-in item (`chronicle:item:<n>`, a dungeon item) a
  mod's own menu icon, `icons/<stem>.png`; leaving out `icon` puts the native one back. One mod per item; unloading
  the mod puts the native icons back.
- `weapons.get().assets` reports `model` and `icon` game paths.
- The model shows once the weapon is equipped (`weapons.equip` in town or a dungeon, or the game's menus).

## Weapon styles (`weapons.style_set`, Chronicle)

- `weapons.style_set({character, slot, name?, color = {r, g, b}?, glow = {r, g, b}?})` gives one owned weapon its own
  name (up to 40 bytes) in the weapon menu, drawn in `color` on the name scroll, and makes its swing trail glow in
  `glow` instead of its element's colour. The style follows the weapon in that slot: another weapon put there doesn't
  inherit it. `weapons.style_clear({character, slot})` takes one back, `weapons.style_clear({})` all of the mod's.
  `badge` (up to 3 lines) and `details` (up to 5) give the weapon a card: while the menu's cursor is on it, one panel
  takes the place of the powder box and the description, with the badge on the left (a rarity, say) and the name
  over the details on the right. Each line is a string or `{text, color = {r, g, b}?, scale = 0.5..1.6?}`, 64 bytes.
  `weapons.get` and `weapons.list` report a retail weapon's own `name` in the game's language.

## Weapon ABS, attachments and build-up

Both games unless an entry says otherwise:

- `game.weapons.abs_get({id = weapon_id, character = optional, slot = optional})`: Reads current ABS (experience
  points), current level, and ABS required for next level.
- `game.weapons.abs_add({id = weapon_id, amount = 50, character = optional, slot = optional})`: Adds ABS to a weapon,
  auto-leveling when reaching the requirement and emitting `game.weapon.abs_gained`. A negative `amount` (down to
  -32767) takes unspent ABS away, never below 0 and never a level; the result's `added` is then negative and no
  `abs_gained` is sent. `slot` needs `character`.
- `game.weapons.attachments_get({id = weapon_id})`: Inspects attachment sockets, filled slots, and stat contributions
  (attack, endurance, speed, magic, elemental, vs-monster).
- `game.weapons.attachment_insert({id = weapon_id, attachment_id = item_id, attachment_slot = optional})`: Inserts an
  attachment into an open socket.
- `game.weapons.attachment_remove({id = weapon_id, attachment_slot = slot_idx})`: (*Chronicle only*) Safely removes an
  attachment from a weapon and returns it to the consumable bag.
- `game.weapons.build_up_list({id = weapon_id})`: Lists available native and mod-registered evolution/build-up targets.
- `game.weapons.build_up_register({from = source_id, to = target_id})`: Dynamically links a custom build-up evolution
  path between two weapons of the same character.
- `game.weapons.synthesize({id = weapon_id})`: (*Chronicle only*) Status-breaks a level 5+ weapon into a SynthSphere
  attachment carrying 60% of its stats.
- `game.weapons.spectrumize({id = weapon_id})`: (*Chronicle Two only*) Spectrumizes a level 5+ weapon into a SynthDrop
  carrying 60% of its stats and synthesis points.

## Shops (`shops.*`)

Reading and changing what the games' shops sell, in both games unless an entry says otherwise:

- `game.shops.list()`: Enumerates native shop catalogs, their NPC owners, and scene locations.
- `game.shops.get({shop = shop_id_or_number})`: Retrieves shop items, stock counts, and purchase prices.
- `game.shops.register_item({shop_no = 0..17 or id = "chronicle:shop:N", item_id = item_id_or_number})`: Adds an item or
  weapon to a shop's stock (a shop holds at most 20 goods). Its price is the item's own (a registered weapon starts at
  its template's); set it with `set_price`, which reaches registered weapons too.
- `game.shops.remove_item({shop_no = 0..17 or id = "chronicle:shop:N", item_id = item_id_or_number})`: Removes an item
  from a shop's inventory.
- `game.shops.set_items({shop_no = 0..17, items = [item_no, ...]})`: (*Chronicle only*) Replaces the native fixed-size
  list with up to 20 goods. Repeated IDs are preserved because native shops use duplicate entries for stock weighting. A
  shorter list retains its `-1` terminator; a full list uses every slot and is read by the game's bounded 20-entry loop.
  The list is owned by the calling mod and restores to its original contents when that mod unloads; another mod cannot
  claim the same shop while it is overridden.
- `game.shops.set_price({item_id = item_id_or_number, buy_price = optional, sell_price = optional})`: Overrides the
  native global buy and/or sell price for an item or weapon. Chronicle restores the original price when the owning mod
  unloads.

Chronicle's `register_item` claims no shop: the goods it adds are kept apart and put back at the end of the list after
any mod's `set_items` (while there is room), so a mod rotating a shop's stock and a mod adding to it both work.
`remove_item` of the caller's own addition takes it back; otherwise `remove_item` and `set_items` share one owner claim
per native shop. `set_price` uses one owner claim per native item price. Conflicting mods receive an error instead of
overwriting another owner's data; unloading the owner restores the saved native value.

## Inventions (Chronicle Two)

Chronicle Two's invention recipes. Chronicle has no inventions, so these are unsupported there.

- `game.inventions.list()` lists native recipes (recipe item, three ideas, and materials) and mod recipes. Native
  recipes come from the game's on-demand `inv6.lst` table; mod recipes are held by the adapter.
- `game.inventions.register({id, item, ideas = {a, b, c}, materials = optional})` registers a namespaced three-idea
  recipe owned by the calling mod. `item` resolves through the normal item/weapon resolver, so a mod item, weapon, or
  ridepod-part item can be the result. Up to four materials are accepted as `{id, count}`. Mod recipes are API-visible
  and craftable, but are not inserted into the native invention-menu recipe table because that table's storage is fixed
  by the game's script data.
- `game.inventions.craft({id, count = 1..99})` requires a native recipe to be discovered (`IsAlreadyCreatedItem`) or a
  mod recipe's three ideas to be learnt. It checks materials, inventory space, consumes materials, and adds the result
  through the native inventory. A successful call queues `game.invention.created` with the item id, native item number,
  three ideas, requested/added counts, and `source = "craft"`; native menu discovery emits the same event with `source =
  "native"`.
