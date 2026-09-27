# Comfy Cloud — LTX-2.5 T2V

**Preferred path:** generation runs **inside the Flutter app** (`MessageAnimScreen` / `ComfyLtxService`).
The desk never sees the API key — phone → Comfy Cloud → frames → BLE.

Desktop script below is optional for debugging the same workflow JSON.

## App (primary)

1. Connect Deskbot in NOVA companion
2. Home → **LTX message**
3. Paste Comfy API key (saved in phone secure storage)
4. Pick a preset or write a prompt → **Generate & play on desk**

Workflow asset: `app/assets/comfy/video_ltx2_5_t2v.json`

## Desktop helper (optional)

```powershell
cd D:\Projects\Deskbot\tools\comfy
pip install -r requirements.txt
copy .env.example .env   # set COMFY_API_KEY
python run_ltx_t2v.py --prompt "..." --duration 4
```
