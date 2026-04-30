# Keystore Setup — Sign Your Play Store Release

This guide creates a release signing keystore and configures GitHub Actions to sign every release build.

⚠️  **CRITICAL:** Once you publish to Play Store with this keystore, you MUST keep it forever. If you lose it, you can NEVER update your app — you'd have to publish a new app from scratch. **Back up to 3 places minimum.**

---

## Step 1 — Run the keystore generation script

Open PowerShell in your project folder and run:

```powershell
.\scripts\generate-keystore.ps1
```

The script will:
1. Ask for a strong password (use the same for both store + key when prompted)
2. Create `vedastro-release.jks` in the current folder
3. Print the base64-encoded version + alias info to copy into GitHub secrets

If you don't have the script yet, see Step 1b below.

---

## Step 1b — If the script doesn't exist yet

Run this single command in PowerShell to generate the keystore manually:

```powershell
keytool -genkey -v `
  -keystore vedastro-release.jks `
  -keyalg RSA `
  -keysize 2048 `
  -validity 10000 `
  -alias vedastro
```

You'll be prompted for:
- **Keystore password** — minimum 6 characters, USE A STRONG ONE (save it in a password manager)
- **First and last name** — your name (e.g. Sarvesh Kumar)
- **Organizational unit** — `VedAstro`
- **Organization** — `VedAstro` (or your business name)
- **City** — your city
- **State** — your state
- **Country code** — `IN`
- **Confirm Y**
- **Key password** — press Enter to use the same as keystore password ✅

After it completes, `vedastro-release.jks` is in your folder.

---

## Step 2 — Convert keystore to base64

Run this in the same PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("vedastro-release.jks")) | Set-Clipboard
Write-Host "✓ Base64 keystore copied to clipboard"
```

The base64 string is now on your clipboard. Don't paste it in chat — just keep it ready for GitHub.

---

## Step 3 — Add GitHub Secrets

**Link:** https://github.com/sarvesh973/vedastro-ai/settings/secrets/actions

Click **"New repository secret"** for each:

| Secret Name | Value |
|---|---|
| `KEYSTORE_BASE64` | (the base64 string from Step 2) |
| `KEYSTORE_PASSWORD` | (the password you chose in Step 1) |
| `KEY_PASSWORD` | (same as keystore password if you pressed Enter) |
| `KEY_ALIAS` | `vedastro` |
| `GEMINI_API_KEY` | (your Gemini API key — already done?) |

Confirm there are 5 secrets total in that page.

---

## Step 4 — Back up the keystore (DO THIS NOW)

Copy `vedastro-release.jks` to **at least 3 places**:

1. ✅ Your password manager (1Password / Bitwarden / Google Drive vault)
2. ✅ A USB drive stored physically separately
3. ✅ An encrypted cloud backup (Google Drive / iCloud)

Also save a `.txt` file alongside each backup with:
```
Keystore password: <your password>
Key alias: vedastro
Key password: <same as above>
Validity: 10000 days from <today's date>
```

Without this file, the keystore is useless.

---

## Step 5 — Test the release build

Push any small commit to trigger the workflow:

```powershell
git commit --allow-empty -m "ci: trigger release build test"
git push
```

Then watch:
**Link:** https://github.com/sarvesh973/vedastro-ai/actions

The build should now produce a **signed** AAB at:
- Artifacts → `VedAstro-AI-aab` → `app-release.aab`

This is what you upload to Play Console.

---

## Step 6 — Delete the local keystore (optional but safer)

Once GitHub secrets are confirmed working AND you've backed up:

```powershell
Remove-Item vedastro-release.jks -Force
```

The local file is no longer needed. GitHub uses the base64 secret on every build.

---

## ⚠️  What NOT to do

| Don't | Why |
|---|---|
| Don't commit `vedastro-release.jks` to git | Becomes public → app gets compromised |
| Don't commit `key.properties` | Contains passwords |
| Don't change the alias once published | Play Store rejects updates |
| Don't lose the keystore | App is permanently un-updatable |
| Don't share the password in chat / email | Use password manager only |

`.gitignore` should already include:
```
android/app/vedastro-release.jks
android/key.properties
*.jks
*.keystore
```

---

## Summary Links

| What | Link |
|---|---|
| GitHub Secrets page | https://github.com/sarvesh973/vedastro-ai/settings/secrets/actions |
| GitHub Actions runs | https://github.com/sarvesh973/vedastro-ai/actions |
| Play Console | https://play.google.com/console |
| keytool docs | https://docs.oracle.com/en/java/javase/17/docs/specs/man/keytool.html |
