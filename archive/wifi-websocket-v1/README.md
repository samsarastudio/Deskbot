# Deskbot

Realtime desk companion: Waveshare ESP32-C6-LCD-1.47 as the robot body, this Windows PC as the brain, Ollama on `10.0.0.54` for language.

## Run the Brain Server

```powershell
cd D:\Projects\Deskbot\brain
py -3 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
py -3 -m deskbot
```

Then open `http://10.0.0.116:8765/` for the device simulator.

WebSocket path for the ESP32:

```
ws://10.0.0.116:8765/deskbot
```

Health: `http://10.0.0.116:8765/health`

## Models

Configured in `brain/config/settings.yaml`:

- Behavior + fast chat: `qwen3.5:0.8b` on CPU (`num_gpu: 0`) so it does not evict the big model
- Hard questions: `gpt-oss:20b` on the NVIDIA GPU at `http://10.0.0.54:11434`

## Firmware (board)

The landscape face (eyes, blinks, centered clock) now lives in `firmware/`. It draws on the onboard ST7789 at 320×172, backlight capped at 50%.

1. Install [ESP-IDF 5.3.1+](https://docs.espressif.com/projects/esp-idf/en/latest/esp32c6/get-started/windows-setup.html) (Espressif installer) and the VS Code / Cursor **ESP-IDF** extension.
2. Plug the board in with USB-C. Hold **BOOT** if the PC does not show a COM port.
3. Edit `firmware/main/app_config.h`:
   - `DESKBOT_WIFI_SSID` / `DESKBOT_WIFI_PASS`
   - `DESKBOT_BRAIN_HOST` (`10.0.0.116` if the Brain Server is this PC)
4. In an ESP-IDF terminal:

```
cd D:\Projects\Deskbot\firmware
idf.py set-target esp32c6
idf.py build flash monitor
```

On success the LCD should show **WAKE**, then **LISTENING** / **IDLE** after Wi-Fi and the brain connect. Clock comes from NTP, or from the brain `hello_ack` time. Keep the Brain Server running first.
