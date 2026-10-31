"""Blender: a character's "Character" collection as glTF for build_character.py.

    blender -b <file.blend> --python export_character.py -- <out.gltf>

Exports the collection (armature and meshes) with Y up, the meshes' skins and custom properties (a material's
`texture`), no animations and no pictures: the pack's textures come from the textures folder.
"""

import sys

import bpy

OUT = sys.argv[sys.argv.index("--") + 1]

layer = bpy.context.view_layer.layer_collection.children.get("Character")
if layer is None:
    raise SystemExit("the file has no \"Character\" collection")
bpy.context.view_layer.active_layer_collection = layer
bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLTF_SEPARATE", use_active_collection=True,
                          export_extras=True, export_animations=False, export_yup=True, export_skins=True,
                          export_image_format="NONE", export_apply=False)
print("EXPORTED", OUT)
