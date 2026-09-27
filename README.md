# NOVA Deskbot — BLE Companion

Phone app (Flutter) + ESP32-C6 Deskbot (NimBLE). Wi‑Fi / PC brain stack is archived under `archive/wifi-websocket-v1/`.

## Identity

- **NOVA** — cute desk character
- **Deskbot** — hardware product (ESP32-C6 + 1.47" ST7789)

## Docs

- [docs/protocol_v1.md](docs/protocol_v1.md) — GATT UUIDs, framing, AUTH, sync
- [docs/BLE_Companion_SOW.md](docs/BLE_Companion_SOW.md) — full SOW
- [docs/QA_MATRIX.md](docs/QA_MATRIX.md) — acceptance / test matrix

## Firmware

```powershell
$env:IDF_TOOLS_PATH = "D:\Espressif"
$env:IDF_PATH = "D:\Espressif\frameworks\esp-idf-v5.5.1"
. D:\Espressif\frameworks\esp-idf-v5.5.1\export.ps1
cd D:\Projects\Deskbot\firmware
idf.py set-target esp32c6
idf.py build
idf.py -p COM5 -b 115200 flash monitor
```

On boot the LCD shows **Open app** (unregistered) or the normal NOVA face with a BLE pip (registered/offline). Advertising name: `NOVA-Setup` or `NOVA`.

## Flutter app

Install [Flutter](https://docs.flutter.dev/get-started/install) then:

```powershell
cd D:\Projects\Deskbot\app
flutter create . --project-name nova_companion --org com.nova
flutter pub get
flutter run
```

`flutter create .` merges platform folders; keep the permissions already in `android/app/src/main/AndroidManifest.xml`.

### First-time flow

1. Grant Bluetooth permission in-app  
2. **Find my Deskbot**  
3. Confirm unit (enter LCD code if shown)  
4. Auto sync → home  

### Daily use

App opens → remembered Deskbot → reconnect + AUTH + delta sync. No Connect button.

## Visual language

Deep navy, cyan ice `#6ee7ff`, gold smiley `#ffd27a`, springy mascot shared with the LCD yellow-circle face.
