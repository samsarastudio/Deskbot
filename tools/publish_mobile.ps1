# Build Android and publish free install links (iOS IPA only on macOS).
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$App = Join-Path $Root "app"
$Dist = Join-Path $Root "dist"
New-Item -ItemType Directory -Force -Path $Dist | Out-Null

if (Test-Path "C:\src\jdk-17") { $env:JAVA_HOME = "C:\src\jdk-17" }
if (-not $env:GRADLE_USER_HOME) { $env:GRADLE_USER_HOME = "D:\.gradle" }
$env:Path = "C:\src\flutter\bin;C:\src\jdk-17\bin;$env:Path"

function Upload-Catbox([string]$File) {
  $r = & curl.exe -s -F "reqtype=fileupload" -F "fileToUpload=@$File" "https://catbox.moe/user/api.php"
  return ("$r").Trim()
}

Write-Host "== Android arm64 release =="
Push-Location $App
try {
  flutter pub get
  flutter build apk --release --split-per-abi
} finally {
  Pop-Location
}

$apk = Join-Path $App "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
$apkOut = Join-Path $Dist "NOVA-android.apk"
Copy-Item $apk $apkOut -Force
$androidUrl = Upload-Catbox $apkOut
Write-Host "Android: $androidUrl"

$iosUrl = ""
Write-Host "Skipping iOS IPA on Windows (needs macOS + Xcode + Apple Team ID)."
Write-Host "On a Mac: edit app/ios/ExportOptions.plist then run tools/publish_mobile.sh"

$stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm") + " UTC"
$htmlPath = Join-Path $Dist "install.html"
# Write HTML without PowerShell parsing CSS custom properties.
$androidEsc = $androidUrl.Replace("&", "&amp;")
@(
  '<!DOCTYPE html>',
  '<html lang="en">',
  '<head>',
  '<meta charset="utf-8"/>',
  '<meta name="viewport" content="width=device-width, initial-scale=1"/>',
  '<title>NOVA install</title>',
  '<style>',
  'body{margin:0;min-height:100vh;font-family:system-ui,sans-serif;background:#070B12;color:#F2F7FC;display:flex;align-items:center;justify-content:center;padding:24px}',
  'main{max-width:420px;width:100%}',
  'h1{font-size:42px;letter-spacing:-.04em;margin:0 0 8px;color:#6EE7FF}',
  'p{color:#8FA3B8;line-height:1.5}',
  'a.btn{display:block;text-align:center;text-decoration:none;margin:14px 0;padding:16px 18px;border-radius:18px;background:linear-gradient(135deg,#9AF4FF,#6EE7FF,#3FC4DE);color:#070B12;font-weight:800}',
  'a.btn.secondary{background:transparent;border:1px solid #2A3A4D;color:#F2F7FC;font-weight:600}',
  'a.btn.disabled{opacity:.45;pointer-events:none}',
  'small{color:#8FA3B8;display:block;margin-top:18px}',
  '</style>',
  '</head>',
  '<body>',
  '<main>',
  '<h1>NOVA</h1>',
  '<p>Install the Deskbot companion on your phone.</p>',
  ('<a class="btn" href="{0}">Install Android APK</a>' -f $androidEsc),
  '<a class="btn secondary disabled" href="#">iOS IPA — needs Mac build</a>',
  '<small>Android: open in Chrome and allow unknown apps. iOS requires a signed IPA from macOS + Xcode (Apple Team ID in app/ios/ExportOptions.plist), then re-run tools/publish_mobile.sh.</small>',
  '</main>',
  '</body>',
  '</html>'
) | Set-Content -Encoding utf8 -Path $htmlPath

$pageUrl = Upload-Catbox $htmlPath
$androidUrl | Set-Content (Join-Path $Dist "android.url")
$pageUrl | Set-Content (Join-Path $Dist "page.url")

$md = @"
# NOVA install links

Updated: $stamp

## Combined install page
$pageUrl

## Android
- APK (arm64): $androidUrl

## iOS
- Not available from this Windows PC.
- On a Mac:
  1. Set Team ID in ``app/ios/ExportOptions.plist``
  2. Run ``bash tools/publish_mobile.sh``
  3. Share the printed iOS + page URLs
"@
Set-Content -Encoding utf8 -Path (Join-Path $Dist "INSTALL.md") -Value $md

Write-Host "Install page: $pageUrl"
Write-Host "Android: $androidUrl"
