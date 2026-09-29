# Releasing

PR Monitor ships as a **Developer ID–signed, notarized** disk image on GitHub Releases. That's how Ice, Rectangle, Loop, Stats and AltTab distribute too. Since macOS 15, Gatekeeper no longer lets people right-click › Open an unsigned app, so notarization isn't optional for a download people can actually open.

Releases are cut from your Mac with one command. `scripts/release.sh`:
1. Archives the app, exports it with your Developer ID, notarizes and staples it.
2. Builds an APFS disk image with an Applications shortcut, then signs, notarizes and staples the image.
3. Writes `dist/SHA256SUMS`.
4. With `--publish`, tags the release and publishes it on GitHub.

## One-time setup (already done)

- **The Developer ID Application certificate** is in your login keychain. Check with `security find-identity -v -p codesigning`.
- **Notarization credentials** are stored under the keychain profile `PRMonitor`. To redo them, create an app-specific password at [account.apple.com](https://account.apple.com) › Sign-In and Security, then run:

  ```bash
  xcrun notarytool store-credentials PRMonitor --apple-id h4saamb@icloud.com --team-id G2537ZRGNU
  ```

## Cutting a release

1. Merge everything for the release into `main`, then check out a clean, up-to-date `main`:

   ```bash
   git checkout main && git pull
   ```

2. Build, notarize, tag and publish in one step:

   ```bash
   NOTARY_PROFILE=PRMonitor scripts/release.sh 1.1.0 --publish
   ```

   It refuses to publish from a dirty or out-of-date checkout, or to reuse an existing tag, so the release always matches the tagged source. Without `--publish`, it only builds into `dist/`, so you can check the build first.

3. Verify. Download the DMG from the release page so it's quarantined like a user's copy, then check it:

   ```bash
   spctl --assess --type open --context context:primary-signature -vv PRMonitor.dmg   # "Notarized Developer ID"
   ```

   Then open the DMG and make sure the app launches with no Gatekeeper warning. The README's Download button always points at the latest `PRMonitor.dmg`.

**Versions:** `MARKETING_VERSION` comes from the version you pass (SemVer). `CFBundleVersion` is the commit count, so it always increases, which update checks rely on.

**Testing the pipeline without signing:** `SIGN_IDENTITY=- scripts/release.sh 0.0.0-test` builds an ad-hoc DMG and skips notarization.

## Optional: releasing from GitHub Actions

`.github/workflows/release.yml` can do the same build on GitHub's machines, but it only runs when started by hand (Actions › Release › Run workflow), and only once these repository secrets exist. It isn't needed for local releases.

| Secret | How to get it |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | In Keychain Access, export the Developer ID Application certificate *with its private key* as a .p12, then `base64 -i cert.p12 \| gh secret set DEVELOPER_ID_P12_BASE64` |
| `DEVELOPER_ID_P12_PASSWORD` | The password you set when exporting the .p12 |
| `APPLE_TEAM_ID` | `G2537ZRGNU` |
| `ASC_API_KEY_P8_BASE64` | App Store Connect › Users and Access › Integrations › Team Keys: create a key with the Developer role and download `AuthKey_XXXX.p8`, then base64-encode it |
| `ASC_KEY_ID` | The key's ID, shown next to it |
| `ASC_ISSUER_ID` | The Issuer ID at the top of the Team Keys page |

## Homebrew

`packaging/homebrew/pr-monitor.rb` is a ready-made cask.

- **Now:** create a `BlockchainHB/homebrew-tap` repository and copy the cask to `Casks/pr-monitor.rb`, with the release's version and DMG `sha256`. Users install with:

  ```bash
  brew install --cask blockchainhb/tap/pr-monitor
  ```

- **Later:** the official `homebrew/cask` requires the app to be notarized, which it is. It also requires notability: about 75 stars, or 225 if you submit your own project. At that point the cask can move there and BrewTestBot bumps it automatically.

## Why not the Mac App Store (yet)

A Mac App Store build is possible, but only as a reduced variant, and it isn't worth doing first:

- **Sandbox required (guideline 2.4.5).** Networking, the keychain, notifications and launch at login all work sandboxed, but **"Continue with GitHub CLI" can't**. Child processes inherit the sandbox, so `gh` couldn't read its own credentials, and running a tool from outside the app bundle is disallowed (2.5.2 and 4.2.3). A Mac App Store build would offer the OAuth sign-in and pasting a token instead.
- **No self-updater** (2.4.5(vii)), and launch at login must be off until the user turns it on.
- **Review needs a working account.** That means a dedicated GitHub test account with seeded pull requests and a token in the review notes, kept valid for every update. Every fix also waits on review.
- **Precedent:** Ice, Rectangle, Loop, AltTab and Stats all skip the store. Maccy ships both.

If it's ever wanted, add an `APPSTORE` build configuration that enables the sandbox with `com.apple.security.network.client`, and compiles out the GitHub CLI option and any updater.

## Next: automatic updates

Add [Sparkle 2](https://sparkle-project.org): generate EdDSA keys, set `SUFeedURL` and `SUPublicEDKey` in `Info.plist`, and have `scripts/release.sh` run `sign_update` and `generate_appcast`, attaching `appcast.xml` to the release. Until then, users update by downloading the new DMG, and a Developer ID signature keeps their keychain access working across versions.
