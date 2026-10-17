# Ascension and Dungeon+ legacy suite integration

This source audit covers the Chronicle packages in MoonFactory. The changes have not been run in the game or a headless test, following the user's instruction. The feature list describes the implementation and available API hooks; gameplay behavior still needs an in-game check.

## Use the current MoonFactory manager

Open **Options > Game+ > Mod Manager**, select Ascension or Dungeon+, and use its existing tabs:

- **Skills**: Ascension's three trees, ranks, prerequisites, and descriptions. Confirm trains the selected skill.
- **Actions**: progression status, casts, respec, weapon mastery, floor tiers, bounty and bestiary status, mutators, and Dungeon+ rewards.
- **Quests / Journal**: Dungeon Feats trophies and their progress and rewards.
- **Settings**: per-level dungeon bonuses and Dungeon+ chance, reward, and speed settings.

The packages do not draw a separate HUD or custom menu. Their visuals and controls use the manager's existing screens and its action notifications.

## Legacy package mapping

- Character progression and combat features from `ascension`, plus weapon kill tracking from `weapon_mastery`, are in **Ascension**.
- The compatible Sturdy water effect is represented by Ascension's Survivalist skill. Aga's Sword's flat incoming-damage guard is also retained.
- Dungeon tier/layout work from `dungeon_plus`, trophies from `dungeon_feats`, floor bounties from `floor_bounty`, mutators from `floor_mutators`, and enemy speed variation from `enemy_variety` are in **Dungeon+**.
- The static item and weapon prices from `expanded_data` are in Dungeon+. The former standalone `hub` and `mod_settings` screens are replaced by MoonFactory's Mod Manager.
- Parts of `expanded_abilities` and `harder_ai` require native hooks the current API does not expose; see the unsupported list below.

## Ascension

Ascension contains 18 skill nodes across Might, Vitality, and Focus. It awards XP on accepted enemy defeats, grants character levels and Paragon ranks, adds native maximum HP on progression, and applies supported combat bonuses through the skill and combat APIs. Skill ranks are limited by the shared party skill-point budget.

Weapon Mastery now belongs to Ascension. Kills count against the equipped stable weapon ID; thresholds are 25, 75, 150, 300, and 600, with a configurable 2% damage bonus per rank by default. The former standalone MoonMod mastery package is a one-time storage import bridge. If it contains saved kills, enable it with Ascension once; its Actions tab also has an import button. It does not own ongoing mastery gameplay.

## Dungeon+

Dungeon+ keeps its per-floor tiers, procedural layout requests, enemy resilience, Gilda bonus, and queued clear rewards. It adds:

- Dungeon Feats: kill, streak, floor-clear, and species milestones with currency rewards in Journal.
- Bestiary records keyed by native enemy model ID. Use **Browse Bestiary** in Actions to inspect entries.
- Floor Bounty: the first enemy type defeated becomes the target; the default target is six kills. Reward scale and kill count are Settings.
- Five floor mutators: Glass Cannon, Iron Hide, Bounty, Fountain, and Scorched. Chance defaults to 35%, plus 3 percentage points per dungeon, capped at 100%; selection persists for that floor visit.
- Enemy speed variety: each living enemy gets a stable per-floor speed roll, default plus or minus 25%. Updates only write native movement intent and skip knockback.
- A static shop-price rebalance with 119 item and weapon records. The package includes the DarkCloud-Expanded BSD-2-Clause notice.

## Legacy features still unsupported or partial

- Lucky Day's chance to double a player hit, other Expanded Abilities weapon procs, and remaining Ascension hit effects need a player weapon-hit hook.
- Enemy revival and the five Harder AI bytecode changes are not included. They need native script compatibility and revival-state hooks.
- Daily rotating shop stock needs a native day counter; only the static price rebalance is included.
- Sturdy's durability refund needs a safe native durability write API.
- Enemy speed writes can be replaced by the game's AI on a later movement step; Dungeon+ reapplies the stable roll while active.
- The bounty target is chosen on the first matching defeat event because floor entry does not publish the initial enemy roster as model IDs.

## Persistence and release status

Progression, skill ranks, floor choices, bestiary records, bounty progress, and mutator selections use package save data or the framework quest journal. Ascension's native maximum HP and MoonMod storage are not transactionally tied to every native game slot; keep progression within one save folder and save after leveling.

No game launch, gameplay test, or headless test was run. This is a source-level integration, not a verified release claim.