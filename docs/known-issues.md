# Known issues

- 2026-11-11: Setup created. Seen on the branches as cloned, in the cloud container:
  - `tools/tests`: `test_embedded_runtime_matches_shared_source` fails (the Chronicle Two patch's
    `lua_runtime.cpp` differs from `src/`). Not yet looked into.
  - `../dc1tk/src`, `cargo test --release`: `rebuild::tests::a_disc_is_not_written_over_the_image_it_is_made_from`
    fails in `dc2tk-disc` ("not an ISO 9660 image"), and cargo stops there, so later crates' tests don't
    run. Use `--no-fail-fast` to see them. Not yet looked into.
  - The cloud container has no game data and no Blender, so in-game and Blender checks run on the user's
    machine only.
