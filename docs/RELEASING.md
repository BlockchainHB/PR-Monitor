# Releasing

PR Monitor ships as a **Developer ID–signed, notarized** disk image on GitHub Releases. That's how Ice, Rectangle, Loop, Stats and AltTab distribute too. Since macOS 15, Gatekeeper no longer lets people right-click › Open an unsigned app, so notarization isn't optional for a download people can actually open.

`scripts/release.sh` does everything: archive, export with Developer ID, notarize and staple the app, build an APFS disk image with an Applications shortcut, sign, notarize and staple the image, and write `dist/SHA256SUMS`. CI runs the same script when a tag is pushed.

## One-time setup

### On your Mac

You need the **Developer ID Application** certificate in your login keychain (check with `security find-identity -v -p codesigning`). You also need notarization credentials, stored once in the keychain:

1. Create an app-specific password at [account.apple.com](https://account.apple.com) › Sign-In and Security › App-Specific Passwords.
2. Store the credentials under a profile name. The command prompts for the password:

   ```bash
   xcrun notarytool store-credentials PRMonitor --apple-id YOUR_APPLE_ID --team-id G2537ZRGNU
   ```

### In GitHub (for automated releases)

Add these under **Settings › Secrets and variables › Actions**:

| Secret | How to get it |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | In Keychain Access, export the Developer ID Application certificate *with its private key* as a .p12, then `base64 -i cert.p12 \| pbcopy` |
| `DEVELOPER_ID_P12_PASSWORD` | The password you set when exporting the .p12 |
| `APPLE_TEAM_ID` | `G2537ZRGNU` |
| `ASC_API_KEY_P8_BASE64` | App Store Connect › Users and Access › Integrations › Team Keys: create a key with the Developer role and download `AuthKey_XXXX.p8`, then `base64 -i AuthKey_XXXX.p8 \| pbcopy` |
| `ASC_KEY_ID` | The key's ID, shown next to it |
| `ASC_ISSUER_ID` | The Issuer ID at the top of the Team Keys page |

## Cutting a release

1. Make sure `main` is green and `swift test` passes.
2. Tag and push:

   ```bash
   git tag v1.0.0 && git push origin v1.0.0
   ```

   The **Release** workflow builds, signs, notarizes, and publishes the release with `PRMonitor.dmg`, `PRMonitor.zip`, and `SHA256SUMS`. The README's Download button always points at the latest `PRMonitor.dmg`.

   To release from your Mac instead:

   ```bash
   NOTARY_PROFILE=PRMonitor scripts/release.sh 1.0.0
   gh release create v1.0.0 dist/PRMonitor.dmg dist/PRMonitor.zip dist/SHA256SUMS --generate-notes
   ```

3. Verify before announcing. Download the DMG from the release page so it's quarantined like a user's copy, then check:

   ```bash
   spctl --assess --type open --context context:primary-signature -vv PRMonitor.dmg   # "Notarized Developer ID"
   ```

   Then open it and make sure the app launches with no Gatekeeper warning.

**Versions:** `MARKETING_VERSION` comes from the tag (SemVer). `CFBundleVersion` is the commit count, so it always increases, which update checks rely on.

**Testing the pipeline without signing:** `SIGN_IDENTITY=- scripts/release.sh 0.0.0-test` builds an ad-hoc DMG and skips notarization.

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

Add [Sparkle 2](https://sparkle-project.org): generate EdDSA keys, set `SUFeedURL` and `SUPublicEDKey` in `Info.plist`, and have the release workflow run `sign_update` and `generate_appcast`, attaching `appcast.xml` to the release. Until then, users update by downloading the new DMG, and a Developer ID signature keeps their keychain access working across versions.
