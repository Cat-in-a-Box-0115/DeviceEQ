# Release procedure

## One-time notarization setup (maintainer, about 10 minutes)

You need a paid Apple Developer Program membership. These steps use your own Apple credentials, so run them yourself; never paste passwords or certificates into issues, chats or the repository.

1. In Xcode → Settings → Accounts, add your Apple ID, then **Manage Certificates → + → Developer ID Application**. Confirm it with `security find-identity -v -p codesigning` and note the full name, e.g. `Developer ID Application: Your Name (TEAMID)`.
2. Create an app-specific password at https://account.apple.com (Sign-In and Security → App-Specific Passwords).
3. Store notarization credentials in your keychain once:
   ```sh
   xcrun notarytool store-credentials deviceeq-notary --apple-id YOU@EXAMPLE.COM --team-id TEAMID
   ```
   It prompts for the app-specific password and saves it under the profile name `deviceeq-notary`.
4. Each release is then one command, which builds, tests, signs, notarizes, staples and packages (it does not upload):
   ```sh
   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./Scripts/notarize-release.sh
   ```
   It prints the `gh release create` command to publish once you've tested the ZIP. The manual steps below describe what it does.

## Each release

The repository can be published as source. An official macOS download should be signed and notarized by its maintainer before being called a signed release.

1. Update the version in `build.sh` and changelog. Run `./build.sh` and `./Tests/verify.sh` on a clean Apple Silicon Mac.
2. Build/sign with your Developer ID Application certificate using `SIGN_IDENTITY`. The build signs its helper first, then the app, with hardened runtime and timestamps. Preserve the chosen bundle identity for future versions. Never commit certificates, private keys or passwords.
3. Create a zip with `ditto -c -k --keepParent build.noindex/DeviceEQ.app DeviceEQ.zip`. Use Apple's `notarytool submit DeviceEQ.zip --keychain-profile YOUR_PROFILE --wait`, then `stapler staple build.noindex/DeviceEQ.app` and `stapler validate build.noindex/DeviceEQ.app`. Recreate the zip after stapling; verify with `spctl --assess --type execute --verbose build.noindex/DeviceEQ.app`.
4. Test the downloaded build on a clean Mac: permission, native volume, import, focus dismissal, EQ off/on, reconnect and clean quit. Don't imply unsupported hardware has passed.
5. Attach the zip and checksum to a GitHub release and describe hardware coverage and limitations. Do not package build caches, profiles, machine diagnostics, downloaded measurement data or signing secrets.

The included CI validates ad-hoc builds only; it does not pretend to notarize or auto-publish. Source publication and release upload are separate manual steps.

## Packaging

After tests, `./Scripts/package-release.sh --local` packages a development app and a clean source archive with checksums. It includes only explicit public source roots and excludes build outputs, Git history and local audio evidence. Review the archive before publishing.

After signing, notarization and stapling, run `./Scripts/package-release.sh --notarized`. This mode requires successful ticket validation and macOS execution assessment; it does not submit to Apple or upload to GitHub. Follow [the release checklist](RELEASE_CHECKLIST.md).
