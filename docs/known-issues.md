# Known issues

- 2026-11-11: Setup created. Seen on the branches as cloned, in the cloud container:
  - `tools/tests`: `test_embedded_runtime_matches_shared_source` fails (the Chronicle Two patch's
    `lua_runtime.cpp` differs from `src/`). Not yet looked into.
  - `../dc1tk/src`, `cargo test --release`: `rebuild::tests::a_disc_is_not_written_over_the_image_it_is_made_from`
    fails in `dc2tk-disc` ("not an ISO 9660 image"), and cargo stops there, so later crates' tests don't
    run. Use `--no-fail-fast` to see them. Not yet looked into.
  - The cloud container has no game data and no Blender, so in-game and Blender checks run on the user's
    machine only.
- 2026-11-11: Agent files written during a session (`.claude/agents/*.md`) are not available as agent types until
  the next session. Until then, run the brief on a general-purpose agent with `model: haiku` and the worker's
  instructions at the top of the prompt.
- 2026-11-11: A cloud session refuses to build third-party source it fetched (SoulsFormats, to compile-check
  `tools/bb/BbModel`): the permission check calls it code from outside. `BbModel` can only be built where
  DSAnimStudio is unpacked, so its check is the user's to run (CLAUDE.md rule 6).
- 2026-11-11: DSAnimStudio's SoulsFormats is not JKAnderson's: a model's `Bones` are `Nodes`, a mesh's
  `DefaultBoneIndex` is `NodeIndex`, a material texture's `Type` is `ParamName`. `BbModel` reads either by name
  (`Member`). Read the fork's source (Meowmaritus/SoulsAssetPipeline, the commit DSAnimStudio pins) before using
  another of its members.
- 2026-11-11: `pip install bpy` works in the cloud container (Blender 5.3 as a Python module, Python 3.13), so
  Blender scripts can be checked there on made-up models.
- 2026-11-11: The dc1tk in this workspace (Jeffiest/dc1tk at `37ca8b0`, `main` and the session branch) does not
  export skin weights. Its source has no `ALLOC_DBUFF` handling and no `chained_weights`, the two toolkit fixes
  `tools/chr/README.md` dates 2026-10-29 and places in the toolkit at `E:/dc1tk-blender`. Seen: `model-export` of
  `mods/moonmod.opar/resources/opar/c07d.chr` (its cfg has `VERTEX_ANIME 1` and `ALLOC_DBUFF "skin"`) gives a glTF
  with no `skins` and no `JOINTS_0`. Until that toolkit work is in the repository, a skinned pack's export and
  build have to come from the build on the user's machine, and nothing built here on this dc1tk can keep a skin.
- 2026-11-11: `dc2tk model-export` refuses a pack that is not inside a game data folder ("one holding dun/ and
  chara/"). A folder with those two directories and the pack at its data path is enough for a pack that needs
  nothing else.
- 2026-11-11: dc1tk builds to `dc1tk/build/release/dc2tk` (its cargo config sets the target folder), not
  `src/target`. Set `DC2TK` to it for `tools/chr/chrtool.py`.
- 2026-11-11: Blender's glTF importer adds a mesh object of its own, `Icosphere` (the bones' shape). A check that
  walks every mesh object meets it first: take the meshes whose parent is the armature. (A first check this
  session stopped on it and was read, wrongly, as the model's mesh missing.)
