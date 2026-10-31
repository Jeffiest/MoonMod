"""MCP server for the MoonMod animation editor: an assistant lists rigs and motions, poses and keys them, saves, and
looks at them, all on the editor page you have open.

    python tools/anim/editor/mcp_server.py [--editor http://127.0.0.1:8765]

It speaks MCP over stdio (JSON-RPC, a message a line) with no packages beyond Python's own. Listing goes straight to
the editor's server; everything else is a command for the open page, carried by the server's bridge (/api/bridge), so
you watch each change and Ctrl+Z undoes it. If the editor isn't running, the first command starts server.py in a
window of its own and opens the page in your browser.
"""

import argparse
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
import webbrowser

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
EDITOR = "http://127.0.0.1:8765"

POSE_NOTE = ("Bones are named as get_pose and list_motions name them. Rotations are local Euler degrees in XYZ order "
             "(the bone panel's numbers); positions are in the model's space, y up, the character facing +z, so its "
             "left is +x.")


def _vec(desc):
    return {"type": "array", "items": {"type": "number"}, "minItems": 3, "maxItems": 3, "description": desc}


TOOLS = [
    {"name": "list_rigs",
     "description": "Every model the editor opens: the party, Opar, and the monsters (group Monsters; Other models are "
                    "parts and props). Use an id with the other tools.",
     "inputSchema": {"type": "object", "properties": {
         "group": {"type": "string", "description": "Only this group: Characters, Monsters or Other models"},
         "search": {"type": "string", "description": "Only rigs whose id or name contains this"}}}},
    {"name": "list_motions",
     "description": "A rig's native motions (index, name, frames, speed), the mod motion files made for it, and its "
                    "animated bones with what each channel can do (rotation, translation, scale).",
     "inputSchema": {"type": "object", "properties": {"rig": {"type": "string"}}, "required": ["rig"]}},
    {"name": "editor_status",
     "description": "What the open page holds: the rig, the motion and its save path, length (frames), speed (frames a "
                    "tick; the game runs 60 ticks a second), the keys and their eases, and the travel preview.",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "open_motion",
     "description": "Opens a rig (if given) and a motion on the page: a native motion by index (a key on every frame; "
                    "edit_motion thin=true keeps the keys that matter), a mod motion file by its repository path, or "
                    "new=true for a new motion holding the current pose.",
     "inputSchema": {"type": "object", "properties": {
         "rig": {"type": "string"},
         "native": {"type": "integer"},
         "file": {"type": "string", "description": "e.g. mods/moonmod.vigil/resources/anims/toan_dive_roll.json"},
         "new": {"type": "boolean"},
         "name": {"type": "string", "description": "For new: the motion's name, used in the default save path"},
         "length": {"type": "integer", "description": "For new: its length in frames (30)"}}}},
    {"name": "get_pose",
     "description": "The pose at a frame: each bone's local rotation (degrees), translation and scale where the motion "
                    "animates them, and its position in the model's space. Hands and feet are 'end' points: not "
                    "animated themselves, but set_pose can reach with them. " + POSE_NOTE,
     "inputSchema": {"type": "object", "properties": {
         "frame": {"type": "integer", "description": "Default: the page's frame"},
         "bones": {"type": "array", "items": {"type": "string"}, "description": "Only these bones"}}}},
    {"name": "set_pose",
     "description": "Keys a pose at a frame (making the key from the blended pose if there is none) as one undo step. "
                    "In order: from_native replaces the whole pose; then each bone's rotation (absolute), turn (added "
                    "on the bone's own axes), translation or move (added); then reach, which bends the two animated "
                    "bones above a hand, foot or bone so it gets to a point, keeping the knee or elbow in the plane it "
                    "bends in. Answers the touched bones and how far each reach fell short. " + POSE_NOTE,
     "inputSchema": {"type": "object", "properties": {
         "frame": {"type": "integer", "description": "Default: the page's frame"},
         "from_native": {"type": "object", "description": "Start from a native motion's frame",
                         "properties": {"motion": {"type": "integer"}, "frame": {"type": "integer"}}, "required": ["motion"]},
         "bones": {"type": "object", "description": "{bone: {rotation|turn: [x,y,z] degrees, translation|move: [x,y,z]}}",
                   "additionalProperties": {"type": "object", "properties": {
                       "rotation": _vec("local Euler degrees, XYZ"), "turn": _vec("degrees added on the bone's axes"),
                       "translation": _vec("local position"), "move": _vec("added to the local position")}}},
         "reach": {"type": "object", "description": "{bone: [x,y,z] in the model's space}",
                   "additionalProperties": _vec("where the bone should be")},
         "ease": {"type": ["string", "null"], "enum": ["in", "out", "inout", None],
                  "description": "The ease into this key from the one before"}}}},
    {"name": "edit_motion",
     "description": "Timing and keys, each change one undo step: undo/redo steps (yours or the user's), delete keys, "
                    "move keys [[from, to]], eases {frame: in|out|inout|null}, length in frames, speed (frames a tick; "
                    "the game runs 60 ticks a second), thin (drop keys the blend reaches anyway, within 1.5 degrees), "
                    "and the travel preview (the engine's lunge, losing decay every tick).",
     "inputSchema": {"type": "object", "properties": {
         "undo": {"type": "integer"}, "redo": {"type": "integer"},
         "delete": {"type": "array", "items": {"type": "integer"}},
         "move": {"type": "array", "items": {"type": "array", "items": {"type": "integer"}, "minItems": 2, "maxItems": 2}},
         "ease": {"type": "object", "additionalProperties": {"type": ["string", "null"]}},
         "length": {"type": "integer"}, "speed": {"type": "number"}, "thin": {"type": "boolean"},
         "travel": {"type": "object", "properties": {
             "show": {"type": "boolean"}, "lunge": {"type": "number"}, "decay": {"type": "number"},
             "backward": {"type": "boolean"}}}}}},
    {"name": "save_motion",
     "description": "Saves the page's motion as a moonmod-motion file (what animations.player_register reads), under "
                    "mods/ or examples/. If the play save has that mod, it is copied there too (sync, default on). "
                    "Monster motions save, but the engine can't play a mod motion on a monster yet.",
     "inputSchema": {"type": "object", "properties": {
         "path": {"type": "string", "description": "Repository path; default: the page's path field"},
         "sync": {"type": "boolean"}}}},
    {"name": "screenshot",
     "description": "Renders the model on the page and returns a PNG. One frame, or several tiled in one picture "
                    "(numbered; a key's number is orange) from one camera that fits them all. Views: three-quarter "
                    "(default), front, back, left, right (the character's), top, or current (the user's camera).",
     "inputSchema": {"type": "object", "properties": {
         "frame": {"type": "integer"},
         "frames": {"type": "array", "items": {"type": "integer"}},
         "view": {"type": "string", "enum": ["three-quarter", "front", "back", "left", "right", "top", "current"]},
         "width": {"type": "integer", "description": "Of one picture (720, or 320 when tiled)"},
         "height": {"type": "integer", "description": "Of one picture (640, or 360 when tiled)"},
         "columns": {"type": "integer", "description": "Tiles a row (up to 6)"},
         "bones": {"type": "boolean", "description": "Draw the bone dots and lines too"}}}},
]

PAGE_COMMANDS = {"editor_status": "status", "open_motion": "open", "get_pose": "get_pose", "set_pose": "set_pose",
                 "edit_motion": "edit", "save_motion": "save", "screenshot": "screenshot"}


class EditorError(Exception):
    pass


def request(path, body=None, timeout=100):
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(EDITOR + path, data=data, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as res:
            return json.loads(res.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            message = json.loads(e.read()).get("error")
        except ValueError:
            message = None
        if e.code == 404 and path.startswith("/api/bridge"):
            message = "this editor server predates the MCP bridge: close its window and start it again"
        raise EditorError(message or "%s %s" % (e.code, e.reason))


def server_up():
    try:
        request("/api/rigs", timeout=5)
        return True
    except (urllib.error.URLError, OSError):
        return False


def start_server():
    """Starts server.py in a console window of its own, as Animation Editor.bat does, and waits for it."""
    port = EDITOR.rsplit(":", 1)[-1].strip("/")
    argv = [sys.executable, os.path.join(HERE, "server.py"), "--port", port]
    if os.name == "nt":
        # no handles of ours: the new console's own (our stdout is the MCP pipe)
        subprocess.Popen(argv, cwd=REPO, creationflags=subprocess.CREATE_NEW_CONSOLE)
    else:
        subprocess.Popen(argv, cwd=REPO, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    for _ in range(60):
        if server_up():
            return
        time.sleep(0.5)
    raise EditorError("the editor server didn't start; run tools/anim/editor/Animation Editor.bat and look at its window")


def ensure_page():
    if not server_up():
        start_server()
    if request("/api/bridge/state")["connected"]:
        return
    webbrowser.open(EDITOR + "/")
    for _ in range(60):
        time.sleep(0.5)
        if request("/api/bridge/state")["connected"]:
            return
    raise EditorError("no editor page connected; open %s/ in a browser" % EDITOR)


def page(cmd, args):
    ensure_page()
    reply = request("/api/bridge/call", {"cmd": cmd, "args": args})
    if not reply.get("ok"):
        raise EditorError(reply.get("error") or "the page failed")
    return reply["result"]


def list_rigs(args):
    if not server_up():
        start_server()
    rigs = request("/api/rigs")
    group, search = args.get("group"), (args.get("search") or "").lower()
    return [r for r in rigs if (not group or r["group"].lower() == group.lower())
            and (not search or search in r["id"].lower() or search in r["name"].lower())]


def list_motions(args):
    if not server_up():
        start_server()
    info = request("/api/rig?id=" + urllib.request.quote(args["rig"]))
    bones = {}
    for c in info["channels"]:
        bones.setdefault(c["bone"], []).append(c["kind"])
    return {"id": info["id"], "name": info["name"], "character": info["character"], "playable": info["playable"],
            "motions": [{"index": m["index"], "name": m["name"], "frames": m["end"] - m["start"], "speed": m["speed"]}
                        for m in info["motions"]],
            "files": info["files"], "bones": [{"bone": b, "channels": k} for b, k in bones.items()]}


def call_tool(name, args):
    """MCP content for one tool call."""
    if name == "list_rigs":
        result = list_rigs(args)
    elif name == "list_motions":
        result = list_motions(args)
    elif name in PAGE_COMMANDS:
        result = page(PAGE_COMMANDS[name], args)
    else:
        raise EditorError("no tool " + name)
    if name == "screenshot":
        png = result.pop("png")
        base64.b64decode(png, validate=True)
        return [{"type": "image", "data": png, "mimeType": "image/png"},
                {"type": "text", "text": json.dumps(result)}]
    return [{"type": "text", "text": json.dumps(result, ensure_ascii=False)}]


def handle(msg):
    method, mid = msg.get("method"), msg.get("id")
    if mid is None:
        return None  # a notification (initialized, cancelled): nothing to answer
    if method == "initialize":
        result = {"protocolVersion": msg.get("params", {}).get("protocolVersion", "2025-06-18"),
                  "capabilities": {"tools": {}},
                  "serverInfo": {"name": "moonmod-animation-editor", "version": "1.0"},
                  "instructions": "Drives the MoonMod animation editor page (tools/anim/editor) the user has open: "
                                  "list rigs and motions, open one, read and key poses, retime, save to a mod, and "
                                  "screenshot frames to check your work. Look before and after you pose."}
    elif method == "ping":
        result = {}
    elif method == "tools/list":
        result = {"tools": TOOLS}
    elif method == "tools/call":
        params = msg.get("params", {})
        try:
            result = {"content": call_tool(params.get("name"), params.get("arguments") or {})}
        except (EditorError, urllib.error.URLError, OSError, KeyError, ValueError) as e:
            result = {"content": [{"type": "text", "text": "%s" % e}], "isError": True}
    else:
        return {"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "no method " + str(method)}}
    return {"jsonrpc": "2.0", "id": mid, "result": result}


def main():
    global EDITOR
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--editor", default=os.environ.get("MOONANIM_EDITOR", EDITOR))
    EDITOR = p.parse_args().editor.rstrip("/")
    out = sys.stdout.buffer
    for line in sys.stdin.buffer:
        if not line.strip():
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            reply = {"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "not JSON"}}
        else:
            reply = handle(msg)
        if reply is not None:
            out.write(json.dumps(reply).encode("utf-8") + b"\n")
            out.flush()


if __name__ == "__main__":
    main()
