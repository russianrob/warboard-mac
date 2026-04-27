# Code Signing & Notarization

When the right secrets are set on the repo, every tag-pushed build is
**code-signed with your Developer ID Application certificate**,
**notarized by Apple**, and **stapled** so end users don't hit
Gatekeeper warnings on first launch.

If the secrets aren't set, the workflow falls back to the unsigned dev
build it produced before — first launch just needs a right-click → Open.

## One-time setup

### 1. Get your Developer ID certificate

In the Apple Developer portal → **Certificates, IDs & Profiles** →
Certificates → **+** → choose **Developer ID Application** (this is the
right cert for distributing outside the Mac App Store; *not*
"Mac Distribution" / "Mac App Distribution").

Download the `.cer` file → double-click to install in Keychain →
in **Keychain Access**, find "Developer ID Application: Your Name (TEAMID)"
→ right-click → **Export** → save as a `.p12` with a password.

### 2. Encode the .p12 for GitHub Actions

```bash
base64 -i certificate.p12 | pbcopy   # macOS — copies to clipboard
# or
base64 -i certificate.p12 -o cert.b64 # writes to a file
```

### 3. Generate an app-specific password

[appleid.apple.com](https://appleid.apple.com) → Sign-In and Security
→ **App-Specific Passwords** → **+** → name it "warboard-mac CI" →
note the 19-char password (`xxxx-xxxx-xxxx-xxxx`).

### 4. Find your Team ID

[developer.apple.com/account](https://developer.apple.com/account) →
Membership Details → "Team ID" (10 characters).

### 5. Add the secrets to the repo

Run these on any machine with `gh` authenticated:

```sh
gh secret set MACOS_CERT_P12_BASE64    --repo russianrob/warboard-mac < cert.b64
gh secret set MACOS_CERT_P12_PASSWORD  --repo russianrob/warboard-mac --body 'YOUR_P12_PASSWORD'
gh secret set APPLE_ID                 --repo russianrob/warboard-mac --body 'you@example.com'
gh secret set APPLE_APP_PASSWORD       --repo russianrob/warboard-mac --body 'xxxx-xxxx-xxxx-xxxx'
gh secret set APPLE_TEAM_ID            --repo russianrob/warboard-mac --body 'XXXXXXXXXX'
```

Or via the GitHub UI: Settings → Secrets and variables → Actions → New
repository secret.

## What the workflow does on tag push

1. Imports the `.p12` into a temporary keychain (deleted after the run)
2. Builds the app with the **Developer ID Application** identity,
   hardened runtime enabled (already on in `project.yml`)
3. Code-signs every framework and helper inside Warboard.app with
   `--options runtime --timestamp`
4. Builds the DMG
5. Submits the DMG to **Apple's notary service** (`xcrun notarytool
   submit --wait`) — typically takes 2–5 minutes
6. **Staples** the notarization ticket to the DMG so Gatekeeper can
   verify offline
7. Signs the stapled DMG with the EdDSA key (Sparkle), updates
   `appcast.xml`, attaches the DMG to the GitHub Release

End users running the resulting DMG see the standard "Are you sure
you want to open this app downloaded from the internet?" prompt the
first time, then nothing on subsequent launches — same UX as any
Mac App Store app.
