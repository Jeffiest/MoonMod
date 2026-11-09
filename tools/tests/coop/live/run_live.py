#!/usr/bin/env python3
"""Live co-op test: two real games through a local relay.

Starts the co-op relay (DC_Web's coop/relay/server.mjs) on 127.0.0.1, then a host game and a guest game, headless at
a real 60 frames a second (DC_HEADLESS_BOUNDED=1), each with its own throwaway save folder holding the co-op mod
(from this repo) and the driver mod (coopdrive/, which plays the scenario's script). The co-op mod's live-test hook
(storage "autotest") makes the host open a room and the guest join it by the code the host's log gives. Both games
log what they see once a second ("COOPTEST state", "DRIVE state"); the scenario's checks read those logs.

    python tools/tests/coop/live/run_live.py                        # the "basic" scenario
    python tools/tests/coop/live/run_live.py --scenario dungeon_follow --keep

Paths default to this machine's layout and can be given: --exe, --dll-dir, --data, --relay.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]

DEFAULTS = {
    'exe': r'E:\Gauntlet-build\dc1-aerial-build\darkcloud.exe',
    'dll_dir': r'E:\Gauntlet-build\Chronicle\port\build\windows-x64-release',
    'data': r'E:\Gauntlet-build\run\data',
    'relay': r'E:\DC_Web\coop\relay\server.mjs',
}
PORT = 7777

# Scenarios: each game's script (coopdrive steps), how long each runs, and the checks (functions of the parsed logs).
# Frames are game frames at 60 a second; the guest starts about when the host's room is open.
SCENARIOS = {}


def scenario(name):
    def add(fn):
        SCENARIOS[name] = fn
        return fn
    return add


@scenario('basic')
def basic():
    """The guest joins the host in Norune; both see each other; the host walks into Divine Beast Cave and the guest
    follows (its follow offer answers itself); the host strikes monsters; the guest leaves; the host carries on."""
    host = [
        # the jump presets' towns have no world area (world.get fails there): start on floor 1 and walk to Norune
        {'when': 'dungeon', 'after': 120, 'op': 'transition', 'id': 'chronicle:location:norune-village'},
        {'when': 'town', 'after': 2700, 'op': 'mark', 'text': 'town together'},  # the guest arrives meanwhile
        {'after': 300, 'op': 'enter_floor', 'dungeon_id': 0, 'floor_id': 1},  # floor 2: floor 1's opening scene holds headless runs
        # strikes once both play on the floor (the walk-ins over: a floor counts as a place only then)
        {'when': 'playing', 'after': 1500, 'op': 'mark', 'text': 'both on the floor'},
        {'when': 'monster', 'after': 30, 'op': 'strike', 'amount': 1000000},  # once one has shown itself
        {'when': 'monster', 'after': 240, 'op': 'strike', 'amount': 1000000},
        {'after': 1500, 'op': 'mark', 'text': 'end'},
    ]
    guest = [
        {'when': 'visit', 'op': 'mark', 'text': 'arrived'},
        {'when': 'dungeon', 'after': 1500, 'op': 'mark', 'text': 'on the floor'},
    ]
    # the guest leaves through the co-op mod (only it may end the visit): 4800 frames after reaching a floor
    return {'host': host, 'guest': guest, 'guest_autotest': {'leave_after': 4800}, 'host_jump': 'dungeon:0', 'host_frames': 14400, 'guest_frames': 13200}


# --- the logs ------------------------------------------------------------------------------------------------------

STATE_RE = re.compile(r'(\w+)=(\[[^\]]*\]|\S+)')


def parse(log_text):
    out = {'coop': [], 'drive': [], 'lines': log_text.splitlines(), 'events': []}
    for line in out['lines']:
        m = re.search(r'(COOPTEST|DRIVE) (.*)$', line)
        if not m:
            continue
        kind, rest = m.groups()
        if rest.startswith('state '):
            fields = dict(STATE_RE.findall(rest[6:]))
            (out['coop'] if kind == 'COOPTEST' else out['drive']).append(fields)
        else:
            out['events'].append(kind + ' ' + rest)
    return out


def peers_of(state):
    text = state.get('peers', '[]').strip('[]')
    peers = {}
    for item in text.split():
        parts = item.split(':')
        # peer:scene...:seen:age:slot, where a scene holds colons itself (D0:0:seed)
        peers[int(parts[0])] = {'scene': ':'.join(parts[1:-3]), 'seen': parts[-3], 'age': int(parts[-2]), 'slot': parts[-1]}
    return peers


def together(a_states, b_states, peer_in_a, peer_in_b, kind):
    """Seconds where both games stood in the same place of `kind` (T town, D dungeon floor) and each showed the other."""
    hits = 0
    for a in a_states:
        sa = a.get('scene', 'nil')
        if not sa.startswith(kind):
            continue
        pa = peers_of(a).get(peer_in_a)
        if pa and pa['scene'] == sa and pa['slot'] != '-':
            hits += 1
    both = 0
    for b in b_states:
        sb = b.get('scene', 'nil')
        if not sb.startswith(kind):
            continue
        pb = peers_of(b).get(peer_in_b)
        if pb and pb['scene'] == sb and pb['slot'] != '-':
            both += 1
    return hits, both


class Checks:
    """The checks of one run, each (ok, label, detail), and the pieces scenarios share."""

    def __init__(self, host, guest, result):
        self.host, self.guest, self.result, self.list = host, guest, result, []

    def check(self, ok, label, detail=''):
        self.list.append((bool(ok), label, detail))

    def ran(self):
        for side in ('host', 'guest'):
            code = self.result[side + '_exit']
            self.check(code == 0, 'the %s game ran to the end' % side, 'exit %s' % code)

    def visit(self):
        g = self.guest['events']
        self.check(any(e.startswith('COOPTEST session visit') for e in g), "the guest's visit started",
                   [e for e in g if 'session' in e or 'status' in e][-4:])

    def together(self, kind, where):
        h, g = together(self.host['coop'], self.guest['coop'], 1, 0, kind)
        self.check(h >= 3, where + ' the host shows the guest', '%d seconds' % h)
        self.check(g >= 3, where + ' the guest shows the host', '%d seconds' % g)

    def scenes(self, who, wanted, label):
        """`who` stood in places matching each of `wanted` (regexes over scene names), in that order."""
        seen = [e.split()[2] for e in getattr(self, who)['events'] if e.startswith('COOPTEST scene ')]
        i = 0
        for scene in seen:
            if i < len(wanted) and re.match(wanted[i] + '$', scene):
                i += 1
        self.check(i == len(wanted), label, ' '.join(seen))

    def no_stray_offers(self, who):
        offers = [e for e in getattr(self, who)['events'] if e.startswith('COOPTEST offer')]
        bad = [e for e in offers if 'floor select' in e or ':-1' in e or ':0 ' in e]
        self.check(not bad, who + ' is never offered a place that is only in transit', bad)

    def pings(self):
        for side in ('host', 'guest'):
            seen = [s.get('pings', '[]') for s in getattr(self, side)['coop'] if s.get('pings', '[]') != '[]']
            self.check(seen, 'the %s measures its ping to the other' % side, seen[-1:] if seen else '')

    def no_errors(self):
        bad = [side + ': ' + l.strip() for side in ('host', 'guest') for l in getattr(self, side)['lines']
               if ('moonmod.coop' in l and ('error' in l.lower() or 'traceback' in l.lower()))
               or "can't go there" in l or 'not in a dungeon or a town' in l]
        self.check(not bad, 'no co-op errors or refused follows', bad[:4])


def check_basic(host, guest, result):
    c = Checks(host, guest, result)
    c.ran()
    c.visit()
    c.together('T', 'in town')
    c.check(any('offer' in e and 'join' in e for e in guest['events']), 'the guest is offered to follow into the cave',
            [e for e in guest['events'] if 'offer' in e])
    c.together('D', 'on the floor')
    c.check(any(s.get('puppets') == 'true' for s in guest['coop'] if s.get('scene', '').startswith('D')),
            "the guest's monsters copy the host's")
    struck = [e for e in host['events'] if re.match(r'DRIVE step \d+ strike ok', e)]
    c.check(len(struck) >= 1, 'the host struck monsters down', [e for e in host['events'] if 'strike' in e])
    # what the host's floor holds alive (sent) against what the guest's copies hold (heard)
    sent = [int(s['mons']) for s in host['coop'] if s.get('scene', '').startswith('D') and s.get('mons', '-') != '-']
    heard = [int(s['mons']) for s in guest['coop'] if s.get('scene', '').startswith('D') and s.get('mons', '-') != '-']
    h_max, g_max = max(sent or [0]), max(heard or [0])
    c.check(h_max > 0 and g_max == h_max, "the guest's copies hold the host's living monsters",
            'host up to %d, guest up to %d' % (h_max, g_max))
    c.check(sent and heard and min(sent) < h_max and min(heard) <= min(sent),
            "a monster the host strikes down is gone from the guest's floor too",
            'host %s..%s, guest %s..%s' % (h_max, min(sent or [0]), g_max, min(heard or [0])))
    c.check(any(e == 'COOPTEST leaving' for e in guest['events']) and
            any(e.startswith('COOPTEST session_ended visit') for e in guest['events']),
            'the guest left by itself', [e for e in guest['events'] if 'leav' in e])
    last = host['coop'][-1] if host['coop'] else {}
    c.check(1 not in peers_of(last) if last else False, 'the host forgets the guest once it has left', last.get('peers'))
    c.pings()
    c.no_stray_offers('guest')
    c.no_errors()
    return c.list


@scenario('floors')
def floors():
    """Floor to floor and home together: the host goes Norune, floor 2, floor 4, back to Norune; the guest follows
    each time by its offer."""
    host = [
        {'when': 'dungeon', 'after': 120, 'op': 'transition', 'id': 'chronicle:location:norune-village'},
        {'when': 'town', 'after': 2700, 'op': 'enter_floor', 'dungeon_id': 0, 'floor_id': 1},
        # headless, a floor's walk-in takes about 1200 frames of Cross presses before play starts on it
        {'when': 'playing', 'after': 2400, 'op': 'enter_floor', 'dungeon_id': 0, 'floor_id': 3},  # floor 3 opens with a scene headless runs can't pass
        {'when': 'playing', 'after': 2400, 'op': 'transition', 'id': 'chronicle:location:norune-village'},
        {'when': 'town', 'after': 1500, 'op': 'mark', 'text': 'end'},
    ]
    guest = [{'when': 'visit', 'op': 'mark', 'text': 'arrived'}]
    return {'host': host, 'guest': guest, 'host_frames': 18000, 'guest_frames': 16800}


def check_floors(host, guest, result):
    c = Checks(host, guest, result)
    c.ran()
    c.visit()
    path = [r'T\d+', r'D0:1:-?\d+', r'D0:3:-?\d+', r'T\d+']
    c.scenes('host', path, 'the host went Norune, floor 2, floor 4, Norune')
    c.scenes('guest', path, 'the guest followed each step')
    c.together('D', 'on the floors')
    c.together('T', 'in town')
    c.no_stray_offers('guest')
    c.no_errors()
    return c.list


@scenario('host_leaves')
def host_leaves():
    """The host closes the room while both stand on a floor: the guest's visit ends and its game goes back to the
    title, and the host plays on alone."""
    host = [
        {'when': 'dungeon', 'after': 120, 'op': 'transition', 'id': 'chronicle:location:norune-village'},
        {'when': 'town', 'after': 2700, 'op': 'enter_floor', 'dungeon_id': 0, 'floor_id': 1},
        {'when': 'dungeon', 'after': 3600, 'op': 'mark', 'text': 'end'},
    ]
    guest = [{'when': 'visit', 'op': 'mark', 'text': 'arrived'}]
    return {'host': host, 'guest': guest, 'host_autotest': {'close_after': 1800}, 'host_frames': 9600,
            'guest_frames': 9000}


def check_host_leaves(host, guest, result):
    c = Checks(host, guest, result)
    c.ran()
    c.visit()
    c.together('D', 'on the floor')
    c.check(any(e == 'COOPTEST closing' for e in host['events']), 'the host closed the room')
    c.check(toast(host, "keeping your guests' things first") and toast(host, "save your game to keep your guests"),
            "the host kept the guest's things before closing", toasts(host))
    c.check(toast(guest, 'the host closed the room; your things were kept'), 'the guest is told its things were kept',
            toasts(guest))
    c.check(any(e.startswith('COOPTEST session_ended visit') for e in guest['events']), "the guest's visit ended",
            [e for e in guest['events'] if 'session' in e or 'status' in e][-4:])
    last_g = guest['drive'][-1] if guest['drive'] else {}
    c.check(last_g.get('session') not in ('visit', None), "the guest's game is back on its own", last_g)
    last_h = host['drive'][-1] if host['drive'] else {}
    c.check(last_h.get('context') == 'dungeon', 'the host plays on alone', last_h)
    c.no_errors()
    return c.list


@scenario('rejoin')
def rejoin():
    """The guest's connection drops while both stand on a floor (the co-op mod's test hook leaves the relay as a
    cable pulled would): its visit goes on alone, it gets back into the room by itself, and both see each other again."""
    host = [
        {'when': 'dungeon', 'after': 120, 'op': 'transition', 'id': 'chronicle:location:norune-village'},
        {'when': 'town', 'after': 2700, 'op': 'enter_floor', 'dungeon_id': 0, 'floor_id': 1},
        {'when': 'dungeon', 'after': 6000, 'op': 'mark', 'text': 'end'},
    ]
    guest = [{'when': 'visit', 'op': 'mark', 'text': 'arrived'}]
    return {'host': host, 'guest': guest, 'guest_autotest': {'drop_after': 1500}, 'host_frames': 12000,
            'guest_frames': 11400}


def check_rejoin(host, guest, result):
    c = Checks(host, guest, result)
    c.ran()
    c.visit()
    g = guest['events']
    c.check('COOPTEST dropping' in g, "the guest's connection was pulled", [e for e in g if 'drop' in e])
    c.check(toast(host, "Guest's connection dropped"), 'the host hears the connection dropped', toasts(host))
    c.check(toast(guest, 'back in the room'), 'the guest gets back into the room by itself', toasts(guest))
    c.check(toast(host, 'is back in (reconnected)'), 'the host hears it is back', toasts(host))
    visits = [e for e in g if e.startswith('COOPTEST session visit')]
    c.check(len(visits) == 1 and not any(e.startswith('COOPTEST session_ended') for e in g),
            'the visit went on through it: no second visit, none ended', visits)
    # after getting back in: on the floor together again
    dropped_at = next((i for i, e in enumerate(guest['lines']) if 'COOPTEST dropping' in e), None)
    after = parse('\n'.join(guest['lines'][dropped_at:]))['coop'] if dropped_at is not None else []
    back = [s for s in after if s.get('link') == 'ok' and s.get('scene', '').startswith('D')
            and peers_of(s).get(0, {}).get('slot', '-') != '-']
    c.check(len(back) >= 3, 'after it, the guest shows the host on the floor again', '%d seconds' % len(back))
    c.pings()
    c.no_errors()
    return c.list


def toasts(side):
    return [l.split('toast ', 1)[1] for l in side['lines'] if 'toast ' in l][-6:]


def toast(side, text):
    return any(text in l for l in side['lines'] if 'toast ' in l)


CHECKS = {'basic': check_basic, 'floors': check_floors, 'host_leaves': check_host_leaves, 'rejoin': check_rejoin}


# --- running -------------------------------------------------------------------------------------------------------

def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2), encoding='utf-8')


def make_save(root, name, autotest, script):
    save = root / 'save'
    if save.exists():
        shutil.rmtree(save)
    (save / 'mods').mkdir(parents=True)
    shutil.copytree(REPO / 'mods' / 'moonmod.coop', save / 'mods' / 'moonmod.coop')
    shutil.copytree(HERE / 'coopdrive', save / 'mods' / 'coopdrive')
    write_json(save / 'moonmod' / 'profile.json', {
        'enabled': {'moonmod.coop': True, 'coopdrive': True},
        'format_version': 1,
        'native_trusted': {},
        'settings': {'moonmod.coop': {'server': 'ws://127.0.0.1:%d' % PORT, 'name': name}},
    })
    write_json(save / 'moonmod' / 'data' / 'moonmod.coop' / 'storage.json', {'autotest': autotest})
    write_json(save / 'moonmod' / 'data' / 'coopdrive' / 'storage.json', {'script': script})
    return save


def launch(args, save, jump, frames, log_path, input_script=None):
    env = dict(os.environ)
    env['DC_HEADLESS_BOUNDED'] = '1'
    env['PATH'] = args.dll_dir + os.pathsep + env.get('PATH', '')
    cmd = [args.exe, '--data', args.data, '--save', str(save), '--headless', '--fast-load', '--jump', jump,
           '--frames', str(frames)]
    if input_script:
        cmd += ['--input', str(input_script)]
    log = open(log_path, 'w', encoding='utf-8', errors='replace')
    return subprocess.Popen(cmd, cwd=args.dll_dir, env=env, stdout=log, stderr=subprocess.STDOUT), log


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--scenario', default='basic', choices=sorted(SCENARIOS))
    for k, v in DEFAULTS.items():
        ap.add_argument('--' + k.replace('_', '-'), dest=k, default=v)
    ap.add_argument('--out', default=None, help='folder for the saves and logs (default: a temp folder)')
    ap.add_argument('--keep', action='store_true', help='keep the folder afterwards')
    args = ap.parse_args()

    out = Path(args.out) if args.out else Path(os.environ.get('TEMP', '/tmp')) / ('coop-live-' + args.scenario)
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    sc = SCENARIOS[args.scenario]()

    relay_log = open(out / 'relay.log', 'w', encoding='utf-8')
    relay = subprocess.Popen(['node', args.relay, '--port', str(PORT), '--host', '127.0.0.1'],
                             cwd=str(Path(args.relay).parent), stdout=relay_log, stderr=subprocess.STDOUT)
    host = guest = None
    logs = []
    try:
        time.sleep(1.5)
        if relay.poll() is not None:
            print('the relay did not start: see', out / 'relay.log')
            return 2
        host_save = make_save(out / 'host', 'Host', dict({'role': 'host', 'where': sc.get('host_where', 'town'), 'follow': False}, **sc.get('host_autotest', {})), sc['host'])
        host, hl = launch(args, host_save, sc.get('host_jump', 'dungeon:0'), sc['host_frames'], out / 'host.log',
                          HERE / sc.get('host_input', 'host_cross.txt'))
        logs.append(hl)
        code = None
        deadline = time.time() + 120
        while time.time() < deadline and host.poll() is None:
            m = re.search(r'COOPTEST room (\S+) role=host', (out / 'host.log').read_text(encoding='utf-8', errors='replace'))
            if m:
                code = m.group(1)
                break
            time.sleep(0.5)
        if not code:
            print('the host opened no room: see', out / 'host.log')
            return 1
        print('room', code)
        guest_save = make_save(out / 'guest', 'Guest', dict({'role': 'guest', 'code': code}, **sc.get('guest_autotest', {})), sc['guest'])
        guest, gl = launch(args, guest_save, 'title', sc['guest_frames'], out / 'guest.log', HERE / 'guest_title.txt')
        logs.append(gl)
        limit = time.time() + max(sc['host_frames'], sc['guest_frames']) / 60 * 8 + 120
        while time.time() < limit and (host.poll() is None or guest.poll() is None):
            time.sleep(1)
        result = {}
        for name, p in (('host', host), ('guest', guest)):
            if p.poll() is None:
                p.kill()
                result[name + '_exit'] = 'killed after the time limit (still running)'
            else:
                result[name + '_exit'] = p.wait()
    finally:
        for p in (host, guest):
            if p is not None and p.poll() is None:
                p.kill()
        for f in logs:
            f.close()
        relay.terminate()
        relay_log.close()

    h = parse((out / 'host.log').read_text(encoding='utf-8', errors='replace'))
    g = parse((out / 'guest.log').read_text(encoding='utf-8', errors='replace'))
    checks = CHECKS[args.scenario](h, g, result)
    failed = 0
    for ok, label, detail in checks:
        print(('  ok   ' if ok else '  FAIL ') + label + ('' if ok or detail == '' else '  [%s]' % (detail,)))
        failed += 0 if ok else 1
    print('%d passed, %d failed  (logs in %s)' % (len(checks) - failed, failed, out))
    if not args.keep and failed == 0:
        shutil.rmtree(out, ignore_errors=True)
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
