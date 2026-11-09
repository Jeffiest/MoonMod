# Co-op playtest checklist

The live harness (`run_live.py`) runs two headless games. Some things only two people at two screens can check.
Go through this after a co-op change, two players, each on their own PC (or two windows on one PC). Write down what
broke, with the time, and send both games' `moonmod.log`.

## Getting in

- [ ] The host presses F8 in a town and gets a room code.
- [ ] The guest types the code on the title page's Online Co-op and joins. They arrive in the host's town.
- [ ] Both HUDs show the room code, "2 of 4", and the other's name with a ping in ms.
- [ ] A wrong code says "no room with that code", not nothing.
- [ ] A host that doesn't answer (the host's game frozen) ends the join after half a minute with a message.

## Playing together

- [ ] In town, each sees the other walking, with the name above.
- [ ] The host walks into a dungeon. The guest gets "Join them there?" and arrives beside the host.
- [ ] Monsters move smoothly on the guest's screen and keep up with the host's (not trailing behind).
- [ ] The guest hits a monster: its HP bar drops at once, and the host's copy loses the same.
- [ ] The guest kills a monster: it dies on both screens.
- [ ] A monster hits the guest: the guest flinches, takes damage, and guard/dodge works.
- [ ] A door or gate one opens opens for the other.
- [ ] Gifting Gilda and an item (F7) works both ways.

## When things go wrong

- [ ] Pull the guest's network cable (or turn Wi-Fi off) for 10 seconds on a floor. The guest keeps playing. Its HUD
      says "reconnecting...". The host hears "Guest's connection dropped". Plug it back in: the guest gets "back in the
      room" within a few seconds, and they see each other again, on the same floor.
- [ ] Do it again for over 2 minutes: the guest gives up, goes back to the title, and is told when its things were last
      kept.
- [ ] Pause the host's game for 15 seconds. The guest's HUD doesn't say "no signal".
- [ ] Freeze the guest's game (drag its window) for 10 seconds. The host's HUD says "Guest (no signal)", then "back
      in touch".
- [ ] "Resync with the host" in the Mod Manager on the guest says it asked the host.

## Leaving

- [ ] The guest presses F10: the host hears "Guest left" (not "connection dropped"). The guest is at the title.
- [ ] The guest joins again: the host says "Guest is back", and the guest has their things from before.
- [ ] The host presses F10 with a guest in: "keeping your guests' things first", then "you closed the room". The
      guest is told "the host closed the room; your things were kept".
- [ ] The host saves, the guest joins again, and their things are the ones from the moment the room closed.
- [ ] The host's game is closed outright (Alt+F4) with a guest in: the guest is told "the host's game left the room;
      your things were last kept N seconds ago".
