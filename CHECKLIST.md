# Next work checklist

Worked top to bottom, one item at a time. An item is ticked when its mod or tool is built, documented and passes
its own headless checks. Each still needs a playtest in the game by someone with a disc; that is noted per item.

Left out on purpose (the user's call, 2026-11-04): Dark Chronicle inventions in Dark Cloud, networking through the
native ABI, porting the Gauntlet and Vigil to Chronicle Two, companion fights and dynamic music.

## Make the base game great

- [x] **1. Modern Cloud (quality of life).** Thirst down to off, slower weapon wear, a weapon break guard that warns
      and stops before a weapon breaks, map and monster reveal options, faster character switches, quick item
      keys, auto-repair from Repair Powder. Built: `mods/moonmod.modern-cloud`, 26 headless checks; needs a playtest.
- [x] **2. Bosses with phases, and Boss Rush.** Story bosses get a name card, an HP bar and a second phase
      below half health, a third near the end. A Boss Rush title mode fights them in a row. Built:
      `mods/moonmod.challenges`, 46 headless checks; needs a playtest, above all the tier numbers. The HP bar is
      top left: the engine has no bottom bar yet.
- [x] **3. Character Paths for the whole party.** The RPG mod's paths for Xiao, Goro, Ruby, Ungaga and Osmond.
      Built: RPG 2.0, three paths and three powers per hero (18 trees), Toan's saves carried over. 33 headless
      checks in `tools/tests/rpg`; needs a playtest of each hero's powers.
- [x] **4. Duels and fishing.** An option to skip or simplify duel QTEs; a written survey of the fishing code
      for a later fishing mod. Done as a survey: skipping already exists in the port's options (Always Win QTEs).
      Easier prompts and a fishing API need engine work, planned in `docs/modding/EVENT_BATTLES_AND_FISHING.md`.

## Mods

- [x] **5. Randomizer with daily seeds.** Chest weapons, shop stock, Atla and floor contents shuffled from one
      seed; a daily seed from the date and a share code. Built: `mods/moonmod.randomizer` (shops, weapon stats,
      monster drops, chest items, floor layouts), 26 headless checks. The engine's `info.get` now reports the date.
      Not shuffled: chest weapons and Atla, which have no API yet. Needs a playtest.
- [ ] **6. The Shaft reborn.** An endless descent title mode: modifiers every ten floors, floor scaling, records.
- [ ] **7. Seda's Chronicle.** A prologue title mode, Seda four hundred years before the game.
- [ ] **8. The eighth hero: Seda.** Seda as a playable character in the Gauntlet and the story, on Opar's pipeline.
- [ ] **9. Living towns.** Villager bounties on dungeon floors, shop stock that follows the story.

## Multipliers

- [ ] **10. Mod browser.** An online index the Mod Manager can read, and a tool that installs from it.
- [ ] **11. Blender add-on for the chr pipeline.** Export a rigged Blender model straight to a Dark Cloud pack.
