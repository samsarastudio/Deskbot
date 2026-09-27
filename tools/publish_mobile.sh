#!/usr/bin/env bash
# Build Android (+ iOS on macOS) and upload free install links to catbox.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/app"
DIST="$ROOT/dist"
mkdir -p "$DIST"

upload() {
  local file="$1"
  curl -s -F "reqtype=fileupload" -F "fileToUpload=@${file}" "https://catbox.moe/user/api.php"
}

echo "== Android arm64 release =="
(
  cd "$APP"
  flutter pub get
  flutter build apk --release --split-per-abi
)
APK="$APP/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
cp -f "$APK" "$DIST/NOVA-android.apk"
ANDROID_URL="$(upload "$DIST/NOVA-android.apk")"
echo "Android: $ANDROID_URL"

IOS_URL=""
if [[ "$(uname -s)" == "Darwin" ]]; then
  echo "== iOS IPA =="
  (
    cd "$APP"
    flutter build ipa --release --export-options-plist=ios/ExportOptions.plist
  )
  IPA="$(ls "$APP"/build/ios/ipa/*.ipa | head -n1)"
  cp -f "$IPA" "$DIST/NOVA-ios.apk.ipa"
  cp -f "$IPA" "$DIST/NOVA-ios.ipa"
  IOS_URL="$(upload "$DIST/NOVA-ios.ipa")"
  echo "iOS: $IOS_URL"
else
  echo "Skipping iOS IPA (needs macOS + Xcode + Apple signing)."
fi

cat > "$DIST/INSTALL.md" <<EOF
# NOVA install links

Updated: $(date -u +"%Y-%m-%d %H:%M UTC")

## Android
- APK (arm64): ${ANDROID_URL}
- Allow Install unknown apps for your browser, then open the link.

## iOS
$(if [[ -n "$IOS_URL" ]]; then echo "- IPA: ${IOS_URL}"; echo "- Install via Safari → Diawi/AltStore/configured profile, or AirDrop the IPA."; else echo "- Not built on this machine. Run \`tools/publish_mobile.sh\` on a Mac with Xcode + Apple Team ID set in \`app/ios/ExportOptions.plist\`."; fi)
EOF

python3 - <<PY
from pathlib import Path
android = """$ANDROID_URL"""
ios = """$IOS_URL"""
html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>NOVA install</title>
<style>
  :root {{ color-scheme: dark; --bg:#070B12; --ink:#F2F7FC; --muted:#8FA3B8; --accent:#6EE7FF; }}
  body {{ margin:0; min-height:100vh; font-family: ui-sans-serif, system-ui, sans-serif;
    background: radial-gradient(1200px 600px at 80% -10%, #1a2a3a, var(--bg)); color: var(--ink);
    display:flex; align-items:center; justify-content:center; padding:24px; }}
  main {{ max-width:420px; width:100%; }}
  h1 {{ font-size:42px; letter-spacing:-.04em; margin:0 0 8px; color:var(--accent); }}
  p {{ color:var(--muted); line-height:1.5; }}
  a.btn {{ display:block; text-align:center; text-decoration:none; margin:14px 0; padding:16px 18px;
    border-radius:18px; background:linear-gradient(135deg,#9AF4FF,var(--accent),#3FC4DE); color:#070B12; font-weight:800; }}
  a.btn.secondary {{ background:transparent; border:1px solid #2A3A4D; color:var(--ink); font-weight:600; }}
  a.btn.disabled {{ opacity:.45; pointer-events:none; }}
  small {{ color:var(--muted); display:block; margin-top:18px; }}
</style>
</head>
<body>
<main>
  <h1>NOVA</h1>
  <p>Install the Deskbot companion on your phone.</p>
  <a class="btn" href="{android}">Install Android APK</a>
  {"<a class='btn secondary' href='"+ios+"'>Install iOS IPA</a>" if ios else "<a class='btn secondary disabled' href='#'>iOS IPA — build on Mac</a>"}
  <small>Android: open in Chrome and allow unknown apps. iOS: signed IPA required (Apple Developer / ad-hoc).</small>
</main>
</body>
</html>"""
Path(r"""$DIST/install.html""").write_text(html, encoding="utf-8")
print("Wrote install.html")
PY

PAGE_URL="$(upload "$DIST/install.html")"
echo "Install page: $PAGE_URL"
echo "$ANDROID_URL" > "$DIST/android.url"
[[ -n "$IOS_URL" ]] && echo "$IOS_URL" > "$DIST/ios.url"
echo "$PAGE_URL" > "$DIST/page.url"
