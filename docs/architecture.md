# MSC Architecture Guide

> **Audience:** a Swift developer's first hour in this repo. Read this alongside the
> code — it explains the load-bearing decisions that aren't obvious from the names alone.

---

## 1. The two-app model

MSC is two separate Xcode projects in one repo:

| App | Path | Role |
|-----|------|------|
| **MSC** (macOS) | `MSCmacOS/` | Hosts server processes, owns all data on disk, serves the Remote API |
| **MSC Remote** (iOS) | `MSCiOS/` | Read/control client; connects to the macOS app over LAN or Tailscale VPN |

The iOS app has **no server knowledge and no data of its own**. Everything it can do — read
status, send commands, install add-ons, manage backups — goes through the Remote API on
port 48400 (default). All server files, configs, and world data live exclusively on the Mac.

The split is intentional: the iOS app is a remote control, not a co-owner. This keeps the
data-safety story simple (one source of truth, one backup target) and means the iOS build
has no filesystem entitlements beyond its own container.

---

## 2. Remote API — provider pattern, registries, and invariants

### Providers

`RemoteAPIServer` is a dependency-free BSD-socket HTTP/WebSocket server. It has **no direct
access to app state**. Instead, every capability it exposes is a mutable closure property:

```swift
var statusProvider:      () -> RemoteAPIStatus
var startProvider:       () -> Void
var commandProvider:     (String) -> Void
var playersProvider:     () -> PlayersResponseDTO
// ...dozens more
```

Route handlers call the closure; `AppViewModel` owns all the real state and supplies it at
wiring time. This keeps the server testable in isolation (stub any provider) and means
Preferences changes (e.g. a new API token) can update the provider in place without
restarting the server.

### Wiring

`AppViewModel.init` must wire two server instances:
- **`shared`** — a long-lived server reused across server switches (the normal path)
- **`api`** — a freshly constructed server when one isn't already running

Both branches call the same umbrella:

```swift
wireProviders(into: server, isoFmt: isoFmt)   // AppViewModel+APIWiring.swift
```

`wireProviders` delegates to eight domain-specific helpers
(`wireInfraProviders`, `wirePlayerAndWorldProviders`, etc., each in their own
`AppViewModel+APIWiring*.swift` file). **This is the M1 invariant**: providers are assigned
once, in one place, and the compiler enforces it by having only one function to call. The
pre-M1 pattern required keeping two hand-synced blocks byte-for-byte identical — a
documented source of bugs.

### The four route registries

Every HTTP route must appear in all four of these sets in `RemoteAPIServer` /
`RemoteAPIServer+HTTP.swift`:

| Registry | Type | Purpose |
|----------|------|---------|
| `adminOnlyPOSTPaths` | `Set<String>` | POSTs that require admin role; guests get 403 |
| `rateLimitedPOSTPaths` | `Set<String>` | POSTs subject to the 10-per-5s rate limiter per IP |
| `pathPermissions` | `[String: String]` | Maps POST path → permission category for named tokens |
| `knownPathsCanonical` | `Set<String>` | Every path the router knows; drives 404-vs-405 distinction |

The invariants:
1. Every `pathPermissions` key must be in `adminOnlyPOSTPaths`.
2. Every `adminOnlyPOSTPaths` entry must be in `rateLimitedPOSTPaths`.
3. Every entry in all three sets must appear in `knownPathsCanonical`.
4. Every path the router `switch` handles must be in `knownPathsCanonical` (and vice versa).

**M2 DEBUG assertions** (added in Prompt 2.4, `validateRegistryIntegrity()`) verify all four
invariants at server startup in DEBUG builds — a missed registration causes a `fatalError`
with a precise message pointing to the missing set. In production builds the server starts
silently; the assertions are compile-time-away via `#if DEBUG`. Run a DEBUG build after
adding a new route to confirm all four registries are in sync before shipping.

Named tokens carry a `[String]` permission list; `pathPermissions` maps each POST path to
the permission string a named token must hold. Admin and guest tokens bypass this map.

---

## 3. DTO evolution conventions

Wire DTOs live in two files that must stay in sync:

- **macOS:** `MSCmacOS/MSCmacOS Swift/RemoteAPIServerDTOs.swift`
- **iOS:** `MSCiOS/MSCRemoteiOS_Swift/RemoteAPIModels.swift`

M3 (Prompt 2.3) added `DTOContractTests.swift` (macOS test target) that round-trips each
DTO pair — run the test suite after any DTO change to catch wire drift.

**Rules for adding fields:**
1. New fields on existing DTOs must be **optional with a default** (`var foo: String? = nil`).
   The iOS and macOS apps may be at different versions; a missing key must decode cleanly.
2. Add a backwards-compatible initialiser overload rather than changing a required init.
3. Use explicit `CodingKeys` only when the wire name must differ from the Swift property
   name. When you rename a property whose wire name must stay stable for iOS compatibility,
   keep the old `CodingKey` value.
4. **Never change a wire field name** that the iOS app already decodes — that's a breaking
   change with no migration path.

**The `dockerContainerRunning` example** (`RemoteAPIStatus`): these fields were named for
the original Docker-backed Bedrock backend. Bedrock now runs in a Virtualization.framework
VM by default, but the wire names are frozen. The fields still carry the active Bedrock
backend's running/status state under the legacy names; the per-field comments in
`RemoteAPIServerDTOs.swift` explain the mismatch. This is the correct handling — rename
the Swift property if needed, but leave the `CodingKey` value unchanged.

---

## 4. The 64 KB body cap

```swift
static let maxRequestBodyBytes: Int = 64 * 1024   // RemoteAPIServer.swift
```

This limit is **architectural, not incidental**. The Remote API runs inside the macOS app
process; a larger cap opens unbounded memory growth from a single malformed request on the
LAN. The cap is documented at the top of `RemoteAPIServerDTOs.swift`.

**Product implication:** every endpoint must be designed around *reference* flows, not raw
file uploads:
- Install a mod → send the catalog item ID, not the JAR bytes
- Restore a backup → send the backup filename, not the zip contents
- Apply a resource pack from URL → send the URL string

If a future feature genuinely needs to accept an arbitrary file (e.g. uploading a custom
JAR), raise the cap explicitly with a matching review of memory and DoS exposure — do not
quietly work around it with chunking or base64 encoding.

---

## 5. Registering a new `.swift` file (pbxproj by hand)

These projects do **not** use Xcode's "Add Files" dialog or synchronized groups. New Swift
files must be registered manually in four sections of
`MSCmacOS/Minecraft_Server_Controller.xcodeproj/project.pbxproj`:

1. **`PBXBuildFile`** — links the source file into the build phase:
   ```
   9AFE02XX2FXXXXXX00XXXXXX /* MyNewFile.swift in Sources */ = {isa = PBXBuildFile; fileRef = 9AFE02YY2FXXXXXX00XXXXXX /* MyNewFile.swift */; };
   ```

2. **`PBXFileReference`** — declares the file on disk:
   ```
   9AFE02YY2FXXXXXX00XXXXXX /* MyNewFile.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MyNewFile.swift; sourceTree = "<group>"; };
   ```

3. **`PBXGroup`** — adds the file reference to the right folder group (find the group that
   contains nearby files and insert alphabetically).

4. **`PBXSourcesBuildPhase`** — adds the build-file entry to the compile sources list.

**ID convention:** existing IDs all start with `9A`. Use a short random suffix that doesn't
collide; the pattern visible in the file is `9AFE02XX` for newer additions. Two IDs are
needed per file (build-file ID and file-reference ID).

**Verify:** after editing the pbxproj, open the project in Xcode or run
`xcodebuild -project "MSCmacOS/Minecraft_Server_Controller.xcodeproj" -scheme MinecraftServerController build`
and confirm the file compiles. A missing section produces a cryptic "no such file" or
"product not found" error.

---

## 6. SwiftUI presentation rules (hard-won; do not violate)

These encode real crashes that required production debugging:

### One presentation modifier per view

Never attach more than one `.alert`, `.sheet`, or `.confirmationDialog` to the same view.
SwiftUI's AttributeGraph resolves only one presentation at a time on a given node; stacking
two on the same view causes one to silently win and the other to never fire, or — worse —
a hang when the dismissed one re-presents.

**Pattern:** attach each secondary presentation to a dedicated `Color.clear` anchor:

```swift
// ✅ correct
Color.clear
    .sheet(isPresented: $showingFirst) { FirstSheet() }
Color.clear
    .alert("Confirm", isPresented: $showingSecond) { ... }

// ❌ crashes / hangs
someView
    .sheet(isPresented: $showingFirst) { FirstSheet() }
    .alert("Confirm", isPresented: $showingSecond) { ... }
```

### Never store an `async` closure as a View property

Storing an `async` closure as a `var` on a SwiftUI `View` struct causes AttributeGraph to
store type metadata that is not safe to read from the render thread — at runtime this
resolves to `0x0` and the app hard-crashes with no useful stack.

```swift
// ❌ hard crash at render time
struct MyView: View {
    var onAction: () async -> Void
    ...
}

// ✅ use a synchronous closure and dispatch internally
struct MyView: View {
    var onAction: () -> Void
    ...
}
```

If the action needs to be `async`, accept a plain `() -> Void` and use `Task { await ... }`
at the call site inside the view.
