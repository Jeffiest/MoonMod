# Dungeon Expeditions

A Chronicle-only MoonFactory example that turns the native dungeon loop into bankable Maze and Horde runs.

## How to play

1. Enable the package in MoonFactory.
2. Open its **Actions** tab and choose **Start Maze Expedition** or **Start Horde Expedition**.
3. Enter or continue through a native dungeon. The package records distinct floors reached and enemy defeats.
4. Use **Bank Expedition** before leaving the dungeon, then return to town to collect Gilda. If already in town, banking settles immediately.
5. Use **Abandon Expedition** to clear the run without a payout.

The Maze contract is to reach four distinct floors. It raises the room count and uses smaller rooms for future generated floors. Its room count and area can be adjusted in the package settings.

The Horde contract is to defeat 25 enemies. It uses large native rooms and raises the number of enemies kept awake at once. Its active-enemy limit can be adjusted in the package settings. The horde mode does not add actors to the game's roster; it makes more of the existing roster participate simultaneously.

A banked reward is calculated from the base reward, distinct floors reached, enemy defeats, and the contract bonus. Reward values are configurable. Reward is capped at 32,767 Gilda per bank.

## Compatibility and boundaries

This first slice uses supported Chronicle APIs for local storage, manager actions, world location, dungeon layout, the active-enemy limit, enemy-defeat events, notifications, and Gilda. It uses native procedural dungeon themes and rooms. It does not create new room geometry, change native enemy AI, or create an independent dungeon map.

Dungeon layout and active-enemy limits are global runtime settings. This package restores their native defaults when a run is banked or abandoned, when the player returns to town, and when the package unloads.
