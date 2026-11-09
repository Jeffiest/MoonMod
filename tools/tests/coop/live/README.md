# Live co-op tests

Two real games playing together through a local relay, headless at a real 60 frames a second, with every check
read from their logs. `test_coop.lua` one folder up checks the co-op mod against a stand-in engine. This harness
checks the real engine, the real relay and both games' timing.

```
python -I tools/tests/coop/live/run_live.py                         # the "basic" scenario
python -I tools/tests/coop/live/run_live.py --scenario floors --keep --out C:/temp/coop-floors
```

Each run starts:

- **The relay**: DC_Web's `coop/relay/server.mjs` on `127.0.0.1:7777`. It needs `npm ci` in that folder once.
- **A host game**: jumped onto Divine Beast Cave floor 1, then walked to Norune. Its co-op mod opens a room.
- **A guest game**: started at the title. Its input opens Online Co-op, and its co-op mod joins the host's room by
  the code the host's log printed.

Each game gets a throwaway save folder holding two mods:

- **The co-op mod**, from `mods/moonmod.coop`. Its live-test hook is read from storage `"autotest"`, which only this
  harness writes. That hook hosts, joins, answers follow offers by itself, and can leave or close the room after a
  while.
- **`coopdrive/`**, which plays the scenario's script: walk to a town, enter a floor, strike monsters, leave.

Both games log what they see once a second (`COOPTEST state ...` and `DRIVE state ...`). The scenario's checks read
those lines.

Scenarios (in `run_live.py`, each with its checks):

| scenario      | what happens |
|---------------|--------------|
| `basic`       | The guest joins in Norune, then follows the host into the cave. The host strikes monsters, and the guest's copies lose them too. The guest leaves and the host forgets it. |
| `floors`      | Norune, floor 2, floor 4, Norune, with the guest following each step. No one is offered a floor that is only loading. |
| `host_leaves` | The host closes the room while both stand on a floor. The guest's things go to the host first, the guest's visit ends, and the host plays on alone. |
| `rejoin`      | The guest's connection drops on a floor (the test hook `drop_after` leaves the relay as a pulled cable would). Its visit goes on, it gets back into the room by itself, and both see each other again. |
| `down`        | Down, not out: on a floor together the guest is knocked out (test hook `knocks`) and lies down; the host, holding Revive (`hold_revive`), gets it up, or it gets up beside the host after the wait. Then both are knocked out: the party fell, and both walk back to Norune. |

`basic` and `rejoin` also check that each game measures its ping to the other. For what only two people at two
screens can check, see `PLAYTEST.md`.

Things to know about headless runs:

- A floor's walk-in takes about 1200 frames of Cross presses before play starts. Floor 1 opens with a story scene,
  and so does floor 3, that headless runs can't get past. So scenarios use floors 2 and 4, and coopdrive's
  `when = "playing"` waits for 60 steady frames of play (`world.get().walking` on a floor).
- The jump presets' towns have no world area, so the host starts on a floor and transitions to Norune.
- Paths default to this machine's layout. Pass `--exe`, `--dll-dir`, `--data` and `--relay` to change them.
