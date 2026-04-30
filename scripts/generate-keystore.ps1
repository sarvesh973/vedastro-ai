# VedAstro AI — Release Keystore Generator
# Run this once to create the signing keystore for Play Store releases.
# After running: copy the base64 output into GitHub Secrets.

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════"
Write-Host "  VedAstro AI — Release Keystore Generator"
Write-Host "═══════════════════════════════════════════════════════════"
Write-Host ""

# Check keytool
$keytool = Get-Command keytool -ErrorAction SilentlyContinue
if (-not $keytool) {
    Write-Host "ERROR: keytool not found." -ForegroundColor Red
    Write-Host "Install Java JDK 17 from: https://adoptium.net/temurin/releases/?version=17"
    Write-Host "Then restart PowerShell and run this script again."
    exit 1
}

# Check existing keystore
$keystorePath = "vedastro-release.jks"
if (Test-Path $keystorePath) {
    Write-Host "WARNING: $keystorePath already exists." -ForegroundColor Yellow
    $confirm = Read-Host "Overwrite? Type YES to continue, anything else to abort"
    if ($confirm -ne 'YES') {
        Write-Host "Aborted. Existing keystore preserved."
        exit 0
    }
    Remove-Item $keystorePath -Force
}

Write-Host ""
Write-Host "STEP 1 — Choose a strong password"
Write-Host "  • Min 12 chars, mix letters/numbers/symbols"
Write-Host "  • SAVE IT IN A PASSWORD MANAGER NOW"
Write-Host "  • You will need it for every Play Store update forever"
Write-Host ""

$password = Read-Host "Enter keystore password" -AsSecureString
$passwordConfirm = Read-Host "Confirm keystore password" -AsSecureString

$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
$plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
$bstr2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($passwordConfirm)
$plain2 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr2)

if ($plain -ne $plain2) {
    Write-Host "ERROR: Passwords don't match. Run script again." -ForegroundColor Red
    exit 1
}
if ($plain.Length -lt 6) {
    Write-Host "ERROR: Password must be at least 6 characters." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "STEP 2 — Identity info (will appear in your APK signature)"
Write-Host ""
$name = Read-Host "Your full name (e.g. Sarvesh Kumar)"
$org  = Read-Host "Organization name (default: VedAstro)"
if (-not $org) { $org = "VedAstro" }
$city = Read-Host "City (e.g. Mumbai)"
$state = Read-Host "State (e.g. Maharashtra)"
$country = Read-Host "Country code (default: IN)"
if (-not $country) { $country = "IN" }

$dname = "CN=$name, OU=$org, O=$org, L=$city, ST=$state, C=$country"

Write-Host ""
Write-Host "STEP 3 — Generating keystore..."
Write-Host ""

$alias = "vedastro"
$validity = "10000"

# Build keytool command
$keytoolArgs = @(
    "-genkey", "-v",
    "-keystore", $keystorePath,
    "-storepass", $plain,
    "-keypass", $plain,
    "-alias", $alias,
    "-keyalg", "RSA",
    "-keysize", "2048",
    "-validity", $validity,
    "-dname", $dname
)

& keytool $keytoolArgs

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: keytool failed." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $keystorePath)) {
    Write-Host "ERROR: Keystore was not created." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "✓ Keystore created: $keystorePath" -ForegroundColor Green
Write-Host ""

# Base64 encode
$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $keystorePath))
$base64 = [Convert]::ToBase64String($bytes)
$base64 | Set-Clipboard

Write-Host "═══════════════════════════════════════════════════════════"
Write-Host "  GITHUB SECRETS — Add these now"
Write-Host "═══════════════════════════════════════════════════════════"
Write-Host ""
Write-Host "Link: https://github.com/sarvesh973/vedastro-ai/settings/secrets/actions"
Write-Host ""
Write-Host "Add these 4 secrets:"
Write-Host ""
Write-Host "  1. KEYSTORE_BASE64"
Write-Host "     Value: (already copied to your clipboard — just paste)"
Write-Host ""
Write-Host "  2. KEYSTORE_PASSWORD"
Write-Host "     Value: (the password you chose)"
Write-Host ""
Write-Host "  3. KEY_PASSWORD"
Write-Host "     Value: (same as KEYSTORE_PASSWORD)"
Write-Host ""
Write-Host "  4. KEY_ALIAS"
Write-Host "     Value: vedastro"
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════"
Write-Host "  ⚠️  BACK UP THIS KEYSTORE TO 3 PLACES" -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════"
Write-Host ""
Write-Host "  1. Password manager (1Password / Bitwarden / Drive vault)"
Write-Host "  2. USB drive stored separately"
Write-Host "  3. Encrypted cloud backup"
Write-Host ""
Write-Host "  ALSO save the password alongside each backup."
Write-Host "  Without it, the keystore is useless."
Write-Host ""
Write-Host "✓ Done. Add the GitHub secrets now."

# Clear sensitive variables
$plain = $null
$plain2 = $null
[System.GC]::Collect()
