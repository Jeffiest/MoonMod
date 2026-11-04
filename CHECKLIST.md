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
- [x] **6. The Shaft reborn.** An endless descent title mode: modifiers every ten floors, floor scaling, records.
      Built: the Shaft on the Challenges row (`mods/moonmod.challenges`), guardians and pacts every ten floors.
      66 headless checks for the mod; needs a playtest.
- [x] **7. Seda's Chronicle.** A prologue title mode, Seda four hundred years before the game. Built: four
      chapters and an epilogue on the Challenges row, on the Shaft's floors and the arena. 93 headless checks for
      the mod. Toan walks in Seda's place until item 8 gives Seda his pack.
- [x] **8. The eighth hero: Seda.** Seda as a playable character in the Gauntlet and the story, on Opar's pipeline.
      Built: his own game model (`c07a`) fitted onto Toan's skeleton by `build_character.py retail` and
      `make_seda.py --retail` (checked on a test model), his registration and roster place in the Gauntlet
      (scenario 30), his Chronicle, and a story join. **Blocked: his pack (`c08d.chr`) is not built**: that needs
      the DC1 toolkit and a disc's data, which this session lacks. Two commands build it (`art/seda/README.md`); the
      rest is in `docs/SEDA_PLAN.md`.
- [x] **9. Living towns.** Villager bounties on dungeon floors, shop stock that follows the story. Built:
      `mods/moonmod.living-towns` (a daily board of four bounty kinds, a villager by the exit gate who pays, general
      stores restocked per dungeon reached), 27 headless checks. Needs a playtest.

## Multipliers

- [ ] **10. Mod browser.** An online index the Mod Manager can read, and a tool that installs from it.
- [ ] **11. Blender add-on for the chr pipeline.** Export a rigged Blender model straight to a Dark Cloud pack.
