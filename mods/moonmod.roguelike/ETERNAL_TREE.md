# Norune Eternal: the unlock sky (design draft 2, built)

*Built 2026-10-28.* The sky is on the title screen: 126 nodes in 14 constellations (the seven below, the heart and
the six Signature skies). 75 nodes (104 ranks) work now, for 816 Moon Shards and 45 Genie Sigils; the rest show as
*Coming soon* until the engine work behind them lands (the Companion, the Signature skies, Moonwalker's dodge roll, Twin
Wardens, Warden's Court, Endless Maze, Blind Halls, Twin Keys, Barren, Loadouts, Blessed Choice, Chosen of the Moon,
Second Wind, Hardy, Clear Mind, Charged Fury, Swift Swap). Differences from the draft below: costs and effects follow
`main.lua`; Unbreakable Bond gives an Auto Repair Powder each biome (the game's own one-break save); Genie's Champions
make each floor's key holder a lesser Warden with twice the HP.

The Gauntlet's permanent progression: a night sky of **seven constellations** around Norune Eternal, each a trunk that
forks into **build paths**, each path ending in a **Keystone** that defines a build. Plus a small **Signature** sky for each
of the six characters. About 125 nodes in all, built to be a long grind with a reason to play every run differently.
Existing unlocks are marked *(now)*.

## How it plays

- **Three currencies.**
  - **Moon Shards** come from every run, as now, and buy most nodes.
  - **Genie Sigils** are rare: 1 per Warden felled at Heat 5 or more, 3 per win, +1 per win at Heat 10, 15 and 20.
    Keystones and the deepest nodes cost Sigils.
  - **Character Marks** go to the character who started the run: 1 per biome cleared. They buy that character's
    Signature sky.
- **Branching.** A node needs one linked node before it, not a whole line. Every constellation forks two or three ways
  after its trunk, and some paths cross over to a neighbouring constellation (*bridges*), so builds can mix.
- **Keystones.** Each path ends in a Keystone, a rule-changing node. **Two Keystones can be on at once** (a third slot
  is itself a late node), so a run is a chosen build: Moonblade with Soul Bond, or Unbreakable Bond with Feast...
- **Switching.** Every bought node can be switched off before a run, and ranked nodes set to any rank owned; switching
  one off keeps everything after it. **Loadouts** save a set of switches under a name (four slots, a node to unlock).
- **Heat.** Pact nodes switched on add Heat; each point pays +10% Moon Shards, and high Heat is where Sigils come from.
  Records keep the best Heat cleared, per character.
- **Stars.** Feats light permanent stars in the sky (no cost, no effect beyond a title and a little Sigil bonus): win
  with each character, win at Heat 10/15/20/max, a win with no curse, a win with one weapon from floor 1-1...

## The seven constellations

Costs: shards unless marked **S** (Sigils). *Keystones in italics.* `→` is a link; a branch lists its paths.

### 1. Arms: the run's weapon
Trunk: **Whetstone** *(now)* I-III (2/4/6) → forks three ways.
- **Edge** (offence): Keen Edge I-III (+5% damage/rank; 5/10/15) → Smith's Start I-III (start one level up/rank;
  5/10/15) → Charged Fury (charged attacks +30%; 12) → Moon Strike I-II (5%/10% crits for double; 15/25) →
  *Moonblade: the first hit on each enemy deals triple* (3 S).
- **Endurance** (durability): Gaffer's Oil *(now)* I-II (3/6) → Field Repair (clearing a floor restores 10%
  durability; 10) → Tempered Grip (no wear for the first 30 s of each floor; 12) → Auto-Repair Charm (start with one;
  12) → *Unbreakable Bond: once per run a break leaves the weapon at 1 instead* (3 S).
- **Craft** (attachments): Macho's Forge *(now)* I-III (4/8/12) → Gem Pouch (start with a gem; 8) → Socket Sense
  (found weapons +1 attachment; 12) → Synth Mastery I-II (absorbing takes 35%/45% instead of 25%; 15/25) →
  *Master's Gift: start with the character's second weapon* (4 S).
- Bridge: **Heirloom Vault** *(now)* (10) sits between Craft and Fortune's Shard path.

### 2. Provisions: what you carry
Trunk: **Repair Kit** *(now)* I-II (2/4) → forks.
- **Water**: Full Waterskin I-II (+1 drop/rank; 3/6) → Spring Sense (Rivers count double; 10) → Deep Breath (no
  thirst damage for 20 s after running dry; 12) → *Endless Spring: water drains half as fast* (2 S).
- **Food**: Baker's Bundle (+2 bread; 3) → Hearty Bread (bread heals 50% more; 8) → Second Helping (+2 bread on each
  biome's floor I; 10) → *Feast: each floor starts with a 20% heal* (2 S).
- **Merchant**: Gaffer's Wagon *(now)* I-II (6/10) → Haggler (Gaffer 20% cheaper; 8) → Gaffer's Stock (he sells
  attachments; 15) → *Gaffer's Partner: the wagon stops on floors II and III* (3 S).

### 3. Allies: who fights with you
Trunk: **Matataki Embassy** *(now)* (12) → forks.
- **Draft**: Golden Atla's Call (drafts in biomes 2 and 4 too; 8) → Shared Spoils I-II (benched allies +25% ABS;
  4/8) → Rally (switching characters heals 10%; 10) → *Full Party: all six are drafted from the start; -10% Moon
  Shards* (3 S).
- **Companion**: Companion (a drafted ally fights beside you: engine-controlled, can't be hurt, its weapon's base
  damage, your lock-on target; switching trades places; 25) → Stances (aggressive or passive; 8) → Keen Partner
  (companion damage +25%; 12) → Twin Strike (hitting what the companion hits: +10% damage; 15) → *Soul Bond: the
  companion's kills feed your weapon's ABS* (3 S).
- **Bench**: Bench Rest (benched allies regain 5% HP a floor; 6) → Swift Swap (no swap cooldown; 10) → *Relay: each
  switch gives the new character 3 s of invincibility* (2 S).

### 4. Fortune: what the run pays
Trunk: **Dran's Shrine** *(now)* I-III (5/10/15) → forks.
- **Shards**: Shard Lens I-III (+10%/rank; 6/12/18) → Cache Sense (caches hold a third treasure; 8) → Lucky Find (5%
  of kills drop a shard; 15) → *Moon Tithe: Wardens pay double shards* (3 S).
- **Blessings**: Moon Blessing *(now)* (15) → Blessed Choice (pick one of three blessings; 15) → Second Blessing
  (20) → *Chosen of the Moon: every blessing counts twice* (4 S).
- **Gilda**: Coin Purse (start with 300 Gilda; 5) → Carts Count (Carts +40% instead of 20%; 10) → Gilda Floors (floors
  pay 60 x depth; 12) → *Treasure Hoard: chests hold one more item* (3 S).

### 5. Diorama: the run's little Norune
Trunk: **Deep Well** *(now)* I-III (5/9/13) → forks.
- **Hearth**: Sturdy Houses (Houses -9% damage taken; 8) → Old Trees (Trees heal twice as often; 10) → *Living
  Norune: keep two placed tiles from run to run* (3 S).
- **Industry**: Mill Rights (Windmill pairs +35%; 10) → Smithy Guild (Smithies -18% wear; 10) → *Industrious: every
  sixth tile is a free extra* (2 S).
- **Light**: Lamp Oil (one Lamp maps the floor and shows monsters; 8) → Moonlit Plots (+2 plots; 12) → *Beacon: Lamps
  also +4% damage each again* (2 S).

### 6. Spirit (new): the character's own strength
Trunk: **Steady Heart** I-III (+10 max HP/rank; 4/8/12) → forks.
- **Guard**: Thick Skin I-II (-5% damage/rank; 8/14) → Second Wind (once a floor, a fatal hit leaves 1 HP; 20) →
  *Last Stand: below 25% HP you deal double damage* (3 S).
- **Speed**: Light Step (+8% run speed; 8) → Quick Gauge (attack gauge refills 20% faster; 12) → *Moonwalker: a dodge
  roll on Circle with a short invincibility* (4 S).
- **Ailments**: Antidote Kit (start with 2 Antidotes; 4) → Hardy (ailments last half as long; 10) → *Clear Mind:
  immune to Freeze and Stamina* (2 S).

### 7. The Dark Genie's Pacts: hardships (Heat)
Trunk: **Crowded Halls** I-II (+25% monsters/rank; 3/6; Heat 1/rank) → forks four ways. Each node adds Heat while on.
- **Beasts**: Hardened Hide I-III (enemies +25% HP; 4/8/12; Heat 1) → Sharp Claws I-II (+20% damage; 5/10; Heat 1)
  → Deeper Dark (enemies as if five floors deeper; 15; Heat 3) → *Genie's Champions: every floor has a mini-Warden*
  (2 S; Heat 3).
- **Labyrinth**: Sprawling Floors I-II (+30% rooms; 5/10; Heat 1) → Blind Halls (no floor map; 8; Heat 1) → Twin Keys
  (exits need two keys; 12; Heat 2) → *Endless Maze: every biome has a fourth floor* (2 S; Heat 3).
- **Scarcity**: Parched Road (water x2; 6; Heat 1) → Brittle Steel (wear +50%; 6; Heat 2) → Lean Start (no kit; 4;
  Heat 1) → *Barren: no chests on floors I-III* (2 S; Heat 3).
- **Wardens**: Twin Wardens I-II (two, then three Wardens; 8/16; Heat 2) → Warden's Rage (Wardens hit 50% harder
  below half HP; 12; Heat 2) → The Genie's Mark (every third floor cursed; 10; Heat 2) → *Warden's Court: the last
  Warden is all five Wardens at once* (3 S; Heat 4).
Pact Keystones don't use the two Keystone slots. Maximum Heat: 40 (Moon Shards x5).

## Signature skies: one per character (Character Marks)

Six small skies of five nodes each, a fork after the second; each ends in a Signature move. Examples:
- **Toan**: Dagger Dance (+15% dagger speed) → Lightning Fang (charged attacks shock) → fork: Swordsman (+1 attachment
  slot on swords) / Wanderer (+1 run speed) → *Atlamillia's Chosen: start with the Atla Sight blessing* .
- **Xiao**: Quick Draw → Pebble Storm (slingshots fire two) → fork: Sniper / Tumbler → *Cat's Nine Lives: survive one
  fall each biome*.
- **Goro**: Iron Grip → Ground Pound (charged attacks shake the room) → fork: Bulwark / Berserker → *Mountain's Might*.
- **Ruby**: Flame Rings → Orb Split → fork: Pyromancer / Moonsinger → *Genie's Daughter*.
- **Ungaga**: Spear Reach → Totem Guard → fork: Warrior / Shaman → *Spirit of the Woods*.
- **Osmond**: Steady Aim → Rocket Boost → fork: Gunner / Scholar → *Moon People's Gift*.
(Final effects to be tuned per character; each costs 1-6 Marks.)

## Totals

| Part | Nodes (ranks) | Shards | Sigils | Marks |
|---|---|---|---|---|
| Seven constellations | 94 (about 125 with ranks) | about 990 | 60 | — |
| Signature skies | 30 | — | — | about 90 |
| Utility (Loadouts, third Keystone slot) | 2 | 40 | 5 | — |

A fresh player banks 10-30 shards a run, a strong one 40-90, and much more at high Heat. Shards alone take 20-30 runs;
the 60 Sigils need about ten wins at Heat 5 or more, and the 90 Marks about 18 cleared runs spread over all six
characters. Buying everything is a 60-100 run grind, and Keystones, Pacts and the six Signature skies give every run a
reason to be different.

## The screen (look A, readable)

A night sky that pans: the cursor's constellation fills the view, the others glow at the edges with their names, and
a small star map in the corner shows the whole sky and where you are. Nodes are the game's item box inside a moon
ring (gold when bought, silver when open, dark when locked; Keystones are larger, crowned rings), joined by dotted
lines to what they need. Nodes carry no labels; path names sit above each path's Keystone. The stone plate at the bottom shows the selected node: name, rank, cost, what it
does, what it needs and what it opens. Top bar: Moon Shards, Sigils, Marks, Heat, Keystones on (1/2).
