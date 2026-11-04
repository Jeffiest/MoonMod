"""MoonMod Character Pack: a Blender add-on for making Dark Cloud character packs (tools/chr).

Install: Edit > Preferences > Add-ons > Install from Disk, pick this file, enable "MoonMod Character Pack". In its
preferences set the MoonMod checkout, the DC1 toolkit (dc2tk.exe) and your game data's dun/mainchara folder.

Then, with a character's .blend open (art/<name>/<name>.blend, made by `build_character.py start`), the 3D view's
sidebar (N) has a MoonMod tab:

- **Check**: the modelling rules of tools/chr/README.md, before a build finds them the slow way: one armature and one
  mesh named `skin` in the Character collection; the skin weighted only to the 20 chain joints, at most 4 a vertex,
  none without; materials named after the pack's pictures (`<pack>02`-`<pack>05`, never `<pack>01`, which the eye
  blink writes); the pictures 256 x 256; the triangle count within reason.
- **Fit Game Model**: for a character the game already has (Seda), `build_character.py retail`: his own model found
  in the game data, fitted onto the template's skeleton, his pictures baked into the pages.
- **Build Pack**: saves the file and runs `build_character.py build`, writing art/<name>/build/<pack>.chr.
- **Install Pack**: copies the built pack into a mod's resources (the folder the mod overrides it from).

The tools run as separate processes with this Blender as theirs, so a build never changes the open file.
"""

bl_info = {
    "name": "MoonMod Character Pack",
    "author": "Jeffiest",
    "version": (1, 0, 0),
    "blender": (5, 2, 0),
    "location": "View3D > Sidebar > MoonMod",
    "description": "Check, fit, build and install Dark Cloud character packs (MoonMod's tools/chr)",
    "category": "Import-Export",
}

import os
import shutil
import subprocess
import sys

import bpy

DEFORM = [
    "jnt1_1", "jnt2_1", "jnt11_1", "jnt12_1",
    "jnt8_1", "jnt9_1", "jnt9_2", "jnt10_1",
    "jnt16_1", "jnt17_1", "jnt17_2", "jnt18_1",
    "jnt22_1", "jnt22_2", "jnt23_1", "jnt24_1",
    "jnt5_1", "jnt5_2", "jnt6_1", "jnt7_1",
]
# name -> its pack (build_character.CHARACTERS); a .blend named otherwise uses the scene's pack name
PACKS = {"opar": "c07d", "seda": "c08d"}
MOD_FOR = {"opar": "moonmod.roguelike/resources/opar", "seda": "moonmod.roguelike/resources/seda"}
MAX_TRIANGLES = 20000
PICTURE = 256


def here_repo():
    """The MoonMod checkout this file sits in (tools/chr/blender/), if it does."""
    root = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
    return root if os.path.exists(os.path.join(root, "tools", "chr", "build_character.py")) else ""


def character_name():
    path = bpy.data.filepath
    return os.path.splitext(os.path.basename(path))[0] if path else ""


def pack_name(scene):
    return PACKS.get(character_name()) or scene.moonmod_pack


# ---------------------------------------------------------------------------------------------------------------------
# The rules


def check_character(scene=None, art=None, pack=None):
    """Problems with the open file as a character to build: a list of (level, text), level "error" or "warning".
    Pure reading; nothing changes."""
    scene = scene or bpy.context.scene
    pack = pack or pack_name(scene)
    art = art or (os.path.dirname(bpy.data.filepath) if bpy.data.filepath else "")
    out = []
    character = bpy.data.collections.get("Character")
    if character is None:
        return [("error", "No collection named Character: the build exports that collection.")]
    arms = [o for o in character.objects if o.type == "ARMATURE"]
    meshes = [o for o in character.objects if o.type == "MESH"]
    if len(arms) != 1:
        out.append(("error", "The Character collection needs exactly one armature (it has %d)." % len(arms)))
    skin = next((o for o in meshes if o.name == "skin"), None)
    if skin is None:
        out.append(("error", "No mesh named skin in the Character collection: the body must be one mesh named skin."))
        return out
    others = [o.name for o in meshes if o is not skin]
    if others:
        out.append(("warning", "Meshes besides skin in Character are exported too: %s." % ", ".join(others[:5])))
    if arms:
        missing = [n for n in DEFORM if n not in arms[0].data.bones]
        if missing:
            out.append(("error", "The armature lacks chain joints: %s. Start from the template's skeleton." % ", ".join(missing[:5])))
        if skin.parent is not arms[0]:
            out.append(("warning", "skin is not parented to the armature."))
        if not any(m.type == "ARMATURE" and m.object is arms[0] for m in skin.modifiers):
            out.append(("warning", "skin has no Armature modifier on the skeleton."))

    groups = {g.index: g.name for g in skin.vertex_groups}
    stray, unweighted, crowded = set(), 0, 0
    for v in skin.data.vertices:
        live = [(groups.get(g.group), g.weight) for g in v.groups if g.weight > 1e-4]
        for name, _ in live:
            if name not in DEFORM:
                stray.add(name)
        if not live:
            unweighted += 1
        if len(live) > 4:
            crowded += 1
    if stray:
        out.append(("error", "skin is weighted to bones that aren't chain joints: %s." % ", ".join(sorted(str(s) for s in stray)[:6])))
    if unweighted:
        out.append(("error", "%d vertices have no weight: they would stay behind when he moves." % unweighted))
    if crowded:
        out.append(("error", "%d vertices have more than 4 weights (the pack keeps 4)." % crowded))

    pages = {pack + "%02d" % i for i in (2, 3, 4, 5)}
    used = set()
    for mat in skin.data.materials:
        if mat is None:
            out.append(("error", "skin has an empty material slot."))
            continue
        name = mat.get("texture", mat.name)
        if name == pack + "01":
            out.append(("error", "%s is the face picture the eye blink writes into: paint on %s-%s." % (name, pack + "02", pack + "05")))
        elif name not in pages:
            out.append(("error", "Material %s is not named after one of the pack's pictures (%s)." % (mat.name, ", ".join(sorted(pages)))))
        used.add(name)
    tris = sum(len(p.vertices) - 2 for p in skin.data.polygons)
    if tris > MAX_TRIANGLES:
        out.append(("warning", "%d triangles: more than %d makes a heavy pack (Opar is about 15,000)." % (tris, MAX_TRIANGLES)))
    if not skin.data.uv_layers:
        out.append(("error", "skin has no UVs."))
    for name in sorted(used & pages):
        png = os.path.join(art, "textures", name + ".png")
        if not os.path.exists(png):
            out.append(("warning", "No picture %s in %s: the template's is kept." % (name + ".png", os.path.join(art, "textures"))))
            continue
        img = bpy.data.images.load(png, check_existing=True)
        if tuple(img.size) != (PICTURE, PICTURE):
            out.append(("error", "%s is %d x %d; the pack's pictures are %d x %d." % (name + ".png", img.size[0], img.size[1], PICTURE, PICTURE)))
    return out


# ---------------------------------------------------------------------------------------------------------------------
# Running the tools


def run_tool(context, *args):
    prefs = context.preferences.addons[__name__].preferences
    repo = prefs.repo or here_repo()
    if not repo:
        raise RuntimeError("Set the MoonMod checkout in the add-on's preferences.")
    if not prefs.mainchara:
        raise RuntimeError("Set the game data's dun/mainchara folder in the add-on's preferences.")
    env = dict(os.environ)
    env["BLENDER"] = bpy.app.binary_path
    if prefs.dc2tk:
        env["DC2TK"] = prefs.dc2tk
    python = prefs.python or sys.executable
    tool = os.path.join(repo, "tools", "chr", "build_character.py")
    out = subprocess.run([python, tool, *args, prefs.mainchara, "--art", os.path.dirname(bpy.data.filepath)],
                         capture_output=True, text=True, env=env)
    text = (out.stdout + out.stderr).strip()
    print(text)
    if out.returncode != 0:
        raise RuntimeError(text.splitlines()[-1] if text else "the tool failed")
    return text


def report_lines(op, text, limit=8):
    for line in text.splitlines()[-limit:]:
        op.report({"INFO"}, line)


class MOONMOD_OT_check(bpy.types.Operator):
    bl_idname = "moonmod.check_character"
    bl_label = "Check"
    bl_description = "Check the open character against the pack's modelling rules"

    def execute(self, context):
        problems = check_character(context.scene)
        context.scene.moonmod_last = "\n".join("%s: %s" % p for p in problems) or "No problems found."
        if not problems:
            self.report({"INFO"}, "No problems found.")
        for level, text in problems:
            self.report({"ERROR" if level == "error" else "WARNING"}, text)
        return {"FINISHED"}


class MOONMOD_OT_build(bpy.types.Operator):
    bl_idname = "moonmod.build_pack"
    bl_label = "Build Pack"
    bl_description = "Save, then build art/<name>/build/<pack>.chr with build_character.py"

    def execute(self, context):
        errors = [t for level, t in check_character(context.scene) if level == "error"]
        if errors:
            self.report({"ERROR"}, "Fix these first (Check): " + errors[0])
            return {"CANCELLED"}
        bpy.ops.wm.save_mainfile()
        try:
            text = run_tool(context, "build")
        except Exception as error:
            self.report({"ERROR"}, str(error))
            return {"CANCELLED"}
        report_lines(self, text)
        context.scene.moonmod_last = text[-2000:]
        return {"FINISHED"}


class MOONMOD_OT_retail(bpy.types.Operator):
    bl_idname = "moonmod.fit_retail"
    bl_label = "Fit Game Model"
    bl_description = "For a character the game already has: fit his own model onto the skeleton (build_character.py retail)"

    def execute(self, context):
        bpy.ops.wm.save_mainfile()
        try:
            text = run_tool(context, "retail")
        except Exception as error:
            self.report({"ERROR"}, str(error))
            return {"CANCELLED"}
        report_lines(self, text)
        bpy.ops.wm.revert_mainfile()  # the tool rewrote the file
        return {"FINISHED"}


class MOONMOD_OT_install(bpy.types.Operator):
    bl_idname = "moonmod.install_pack"
    bl_label = "Install Pack"
    bl_description = "Copy the built pack into the mod that registers him"

    def execute(self, context):
        prefs = context.preferences.addons[__name__].preferences
        repo = prefs.repo or here_repo()
        pack = pack_name(context.scene)
        built = os.path.join(os.path.dirname(bpy.data.filepath), "build", pack + ".chr")
        if not os.path.exists(built):
            self.report({"ERROR"}, "No built pack at %s: Build Pack first." % built)
            return {"CANCELLED"}
        target = context.scene.moonmod_install or MOD_FOR.get(character_name(), "")
        if not target:
            self.report({"ERROR"}, "Set the mod folder to install into (mods/<mod>/resources/<name>).")
            return {"CANCELLED"}
        folder = os.path.join(repo, "mods", target) if not os.path.isabs(target) else target
        os.makedirs(folder, exist_ok=True)
        shutil.copy2(built, os.path.join(folder, pack + ".chr"))
        self.report({"INFO"}, "Installed %s.chr in %s" % (pack, folder))
        return {"FINISHED"}


class MOONMOD_PT_panel(bpy.types.Panel):
    bl_label = "Character Pack"
    bl_idname = "MOONMOD_PT_character_pack"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "MoonMod"

    def draw(self, context):
        col = self.layout.column()
        name = character_name()
        col.label(text="Character: %s" % (name or "(save the file first)"))
        if name not in PACKS:
            col.prop(context.scene, "moonmod_pack")
        else:
            col.label(text="Pack: %s" % PACKS[name])
        col.operator(MOONMOD_OT_check.bl_idname, icon="CHECKMARK")
        col.operator(MOONMOD_OT_retail.bl_idname, icon="IMPORT")
        col.operator(MOONMOD_OT_build.bl_idname, icon="EXPORT")
        col.prop(context.scene, "moonmod_install")
        col.operator(MOONMOD_OT_install.bl_idname, icon="FILE_FOLDER")
        if context.scene.moonmod_last:
            box = col.box()
            for line in context.scene.moonmod_last.splitlines()[:10]:
                box.label(text=line[:90])


class MOONMOD_Preferences(bpy.types.AddonPreferences):
    bl_idname = __name__
    repo: bpy.props.StringProperty(name="MoonMod checkout", subtype="DIR_PATH", default="")
    dc2tk: bpy.props.StringProperty(name="DC1 toolkit (dc2tk)", subtype="FILE_PATH", default="")
    mainchara: bpy.props.StringProperty(name="Game data's dun/mainchara", subtype="DIR_PATH", default="")
    python: bpy.props.StringProperty(name="Python for the tools (default: Blender's)", subtype="FILE_PATH", default="")

    def draw(self, context):
        for prop in ("repo", "dc2tk", "mainchara", "python"):
            self.layout.prop(self, prop)


CLASSES = (MOONMOD_OT_check, MOONMOD_OT_build, MOONMOD_OT_retail, MOONMOD_OT_install, MOONMOD_PT_panel, MOONMOD_Preferences)


def register():
    for cls in CLASSES:
        bpy.utils.register_class(cls)
    bpy.types.Scene.moonmod_pack = bpy.props.StringProperty(name="Pack", default="c09d",
                                                            description="The new pack's name, 4 letters like the template's")
    bpy.types.Scene.moonmod_install = bpy.props.StringProperty(name="Install into", default="",
                                                               description="mods/<this>: the mod's resources folder for the pack")
    bpy.types.Scene.moonmod_last = bpy.props.StringProperty(default="")


def unregister():
    for cls in reversed(CLASSES):
        bpy.utils.unregister_class(cls)
    for prop in ("moonmod_pack", "moonmod_install", "moonmod_last"):
        delattr(bpy.types.Scene, prop)


if __name__ == "__main__":
    register()
