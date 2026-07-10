# Releasing Minecraft Server Controller (macOS)

This produces a **Developer ID-signed, notarized, stapled** build that opens on other
people's Macs without the Gatekeeper "unidentified developer" wall.

The whole thing is scripted in [`scripts/release-macos.sh`](../scripts/release-macos.sh).
You run it; it archives, re-signs with your Developer ID cert, submits to Apple's notary
service, staples the ticket, and drops a versioned `.zip` in `dist/`.

---

## One-time setup (human, ~10 minutes)

You need an active **Apple Developer Program** membership. Do these once per machine.

### 1. Create a "Developer ID Application" certificate

In **Xcode → Settings → Accounts**:

1. Select your Apple ID → your team (**Cameron Temple, 6898622Y3Y**).
2. Click **Manage Certificates…**
3. Click **+** in the bottom-left → **Developer ID Application**.
4. Done — it lands in your login keychain.

Verify from the terminal:

```sh
security find-identity -v -p codesigning | grep "Developer ID Application"
```

You should see: `Developer ID Application: Cameron Temple (6898622Y3Y)`.

> This certificate is **already present** on the current build machine — you can skip
> this step there and go straight to notary credentials.

### 2. Store notary credentials in a keychain profile

The script authenticates to Apple's notary service through a keychain profile named
**`MSC_NOTARY`**. Create it once. The easiest credential is an **app-specific password**:

1. Generate one at <https://account.apple.com> → **Sign-In and Security → App-Specific
   Passwords → +**. Name it e.g. `MSC notarytool`. Copy the `xxxx-xxxx-xxxx-xxxx` value.
2. Store it:

```sh
xcrun notarytool store-credentials "MSC_NOTARY" \
  --apple-id "elitetemplex@gmail.com" \
  --team-id "6898622Y3Y" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

That writes the credential into your keychain; you never pass it again.

<details>
<summary>Alternative: App Store Connect API key (no password, better for CI)</summary>

Create an API key at App Store Connect → **Users and Access → Integrations → App Store
Connect API**, download the `AuthKey_XXXX.p8`, then:

```sh
xcrun notarytool store-credentials "MSC_NOTARY" \
  --key "/path/to/AuthKey_XXXX.p8" \
  --key-id "<KEY_ID>" \
  --issuer "<ISSUER_UUID>"
```
</details>

Confirm the profile works:

```sh
xcrun notarytool history --keychain-profile "MSC_NOTARY"
```

---

## Cutting a release

1. Bump `MARKETING_VERSION` in the macOS target if this is a new version (currently `1.13`).
2. Run the pipeline from the repo root:

   ```sh
   scripts/release-macos.sh
   ```

   It prints each step. Notarization usually finishes in a few minutes. On success you get:

   ```
   dist/MinecraftServerController-<version>.zip
   ```

   which is fully notarized and stapled (works offline, no Gatekeeper warning).

3. Tag and publish (see tagging convention below), attaching that `.zip` to the release.

### Useful flags

- `SKIP_NOTARIZE=1 scripts/release-macos.sh` — archive, export, and Developer ID re-sign
  only. Produces a **signed but not notarized** app for quick local testing without
  contacting Apple. Handy before your notary credentials exist.
- `NOTARY_PROFILE=SomeOtherName scripts/release-macos.sh` — use a differently-named
  keychain profile.

### What the script verifies for you

- The exported app is actually signed by **Developer ID Application** (fails loudly if it
  somehow re-signed with the development cert).
- After stapling, it runs `stapler validate` and `spctl -a -vv` and prints the Gatekeeper
  verdict. A good result ends with `source=Notarized Developer ID` and `accepted`.

---

## Signing design (why the pbxproj was left alone)

The project's Release config keeps `CODE_SIGN_IDENTITY = "Apple Development"` with
automatic signing — **unchanged**. The Developer ID identity is applied only at export
time by [`scripts/exportOptions.plist`](../scripts/exportOptions.plist) (`method:
developer-id`, manual signing with the `Developer ID Application` cert). This was chosen
over editing the target's signing settings because:

- Everyday Release builds and the CI job (which builds with `CODE_SIGNING_ALLOWED=NO`)
  keep working exactly as before — the release identity is not baked into the project.
- The Debug config is untouched, as required.
- It's Apple's recommended archive-then-export flow; the hardened runtime (already enabled
  on the target) carries into the export, so the result is notarization-ready.

The app is unsandboxed and holds a single entitlement,
`com.apple.security.virtualization` (needed for the in-process Bedrock VM). That
entitlement does **not** require a provisioning profile for Developer ID distribution, so
the export runs offline against the local certificate.

---

## Tagging & GitHub Release convention

- Tag each release `vX.Y` (matching `MARKETING_VERSION`) on the release commit:

  ```sh
  git tag v1.13
  git push origin v1.13
  ```

- Create a **GitHub Release** for that tag and attach
  `dist/MinecraftServerController-<version>.zip`.
- The current history has only `v1.0` tagged against a marketing version of `1.13` — the
  first modern release should back-tag or cut `v1.13` so the (planned) in-app
  "Check for Updates…" has something newer than `v1.0` to find.

> Version-bump checklist: `MARKETING_VERSION` → run `scripts/release-macos.sh` → tag
> `vX.Y` → GitHub Release with the notarized zip + notes.
