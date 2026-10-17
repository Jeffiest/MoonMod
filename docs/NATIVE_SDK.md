# Native SDK

MoonFactory provides a C-compatible native plugin ABI v1 and an opt-in dynamic loader. Lua remains the default creator API. A native plugin is an in-process extension and runs with the game's process authority after the user separately trusts its package in the local mod manager. The published ABI symbols retain their `MoonMod` names for compatibility.

## Trust boundary

Native code is not sandboxed. It can access the process and the current user's operating-system permissions directly; manifest permissions only govern host services. The mod manager shows a separate trust confirmation for each package's declared library and lists every permission declared by that package. The profile approval is bound to the package version, library path, file size, last-modified time, and SHA-256 digest. A changed library requires local approval again. This detects package updates; it is not a publisher signature or a sandbox.

The loader accepts only a package-relative `.dll`, `.so`, or `.dylib` path whose canonical target remains inside the package and whose size is at most 256 MiB. A package must declare the `native.extension` manifest permission and a `native_extension.library` path. The library is never loaded before local trust is recorded. On Windows the loader uses restricted `LoadLibraryExW` search flags; POSIX builds use `dlopen` with immediate symbol resolution and local symbol visibility.

```json
{
  "schema_version": 1,
  "id": "example.native-probe",
  "name": "Native Probe",
  "version": "1.0.0",
  "framework_api": 1,
  "games": ["chronicle", "chronicle-two"],
  "entry": "main.lua",
  "permissions": ["native.extension", "game.read"],
  "native_extension": {"library": "native/probe.dll"}
}
```

The mod manager's `N?` badge means the library is not trusted; `N+` means its current fingerprint is trusted. Select that badge or focus it with the manager's pane navigation, then confirm the warning to trust or revoke trust. Trust may be granted while the mod is disabled; the library only loads when the package is enabled.

## ABI v1

Include [`../include/moonmod/native_plugin.h`](../include/moonmod/native_plugin.h). It is valid C and C++, uses fixed-width integer fields, and exports no C++ standard-library types. A library exports `MoonMod_GetNativePluginV1`, which returns a `MoonModNativePluginV1` descriptor. The descriptor includes ABI version and size, a package-matched plugin id, minimum host ABI, a list of required manifest permissions, and load/unload callbacks. Every requested permission must be known and declared by the package.

The host service table is size tagged and identifies the game, build label, and platform. V1 services provide logging, capability queries, JSON calls to supported game-adapter operations and JSON-callable core APIs, and event subscribe/unsubscribe. Core calls run through the package's loaded Lua runtime, so they share its storage, exported functions, permission checks, and native game adapters. Host API calls enforce both the descriptor's requested permissions and the manifest permissions. Native `api_call_json` arguments are a JSON array, matching the Lua call's positional arguments. Callback-based APIs such as `commands.register` and `scripts.register_function` cannot be passed through JSON; event callbacks use the native host's subscribe/unsubscribe services. `api.call` is not exposed to native plugins because its nested dispatch could bypass the plugin descriptor's requested permission boundary.

Host calls and event callbacks are valid on the game thread. A plugin may own up to 128 event subscriptions; the runtime removes them after the unload callback, including when load fails. Unload is called before the library is released. Buffer lengths exclude NUL; JSON and text output is NUL terminated when the provided capacity is sufficient. A short buffer reports its required length.

```c
#include "moonmod/native_plugin.h"

static MoonModNativeStatusV1 load_plugin(const MoonModNativeHostV1 *host,
                                         void **state,
                                         MoonModNativeBufferV1 *error_message);
static void unload_plugin(const MoonModNativeHostV1 *host, void *state);

static const char *const permissions[] = {"game.read", "native.extension"};
static const MoonModNativePluginV1 plugin = {
    (uint32_t)sizeof(MoonModNativePluginV1),
    MOONMOD_NATIVE_ABI_MAJOR_V1,
    MOONMOD_NATIVE_ABI_MINOR_V1,
    MOONMOD_NATIVE_ABI_MAJOR_V1,
    MOONMOD_NATIVE_ABI_MINOR_V1,
    "example.native-probe",
    2,
    permissions,
    load_plugin,
    unload_plugin
};

MOONMOD_NATIVE_PLUGIN_EXPORT const MoonModNativePluginV1 *MoonMod_GetNativePluginV1(void) {
    return &plugin;
}
```

## Verification

Both ports compile a C shared-library fixture and run it through the real package/runtime loader. Headless tests verify the plugin stays unloaded before local trust, receives game identity and host services, calls a supported native API, subscribes to a tick, unloads and releases that subscription, reloads under saved trust, and requires approval again after the file metadata changes. A SHA-256 known-vector test checks the fingerprint implementation, while ABI contract cases reject incompatible descriptors. The current Windows headless run exercises the Windows loader path; Linux and macOS loader branches still need platform CI coverage.
