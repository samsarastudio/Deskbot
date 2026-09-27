# Deskbot / NOVA BLE Protocol v1

Phone = BLE Central (GATT Client). ESP32-C6 Deskbot = BLE Peripheral (GATT Server, NimBLE).

## Identity

| Field | Value |
|-------|-------|
| Product | Deskbot |
| Character | NOVA |
| Protocol version | `1` |
| Firmware model string | `deskbot-c6-147` |

## UUIDs (128-bit)

Base: `6e6f7661-0000-4000-8000-6465736b626f` (“nova…deskbo”)

| Element | UUID |
|---------|------|
| Primary service | `6e6f7661-0001-4000-8000-6465736b626f` |
| Command RX | `6e6f7661-0002-4000-8000-6465736b626f` |
| Event TX | `6e6f7661-0003-4000-8000-6465736b626f` |
| Device Info | `6e6f7661-0004-4000-8000-6465736b626f` |
| Control / Session | `6e6f7661-0005-4000-8000-6465736b626f` |

Manufacturer company ID (adv): `0xFFFF` (development). Manufacturer payload:

```
[0x01][protocol=1][flags][device_id_short 4 bytes]
```

Flags bit0 = registered, bit1 = setup-available.

## GATT properties

| Char | Properties | Direction |
|------|------------|-----------|
| Command RX | Write, Write Without Response | App → Deskbot |
| Event TX | Notify | Deskbot → App |
| Device Info | Read | App ← Deskbot |
| Control / Session | Read, Write, Notify | Bidirectional session |

## Connection state machine

```
UNREGISTERED → REGISTERED_OFFLINE → CONNECTING → AUTHENTICATING
  → SYNCING → CONNECTED
RECONNECTING (from CONNECTED on link loss)
RECOVERY (auth fail / protocol mismatch / reset)
```

## Framing & fragmentation

All payloads are UTF-8 JSON objects wrapped in binary frames for MTU-safe transport.

### Frame header (6 bytes)

| Offset | Size | Field |
|--------|------|-------|
| 0 | 1 | `0xA5` magic |
| 1 | 1 | flags (`0x01` = more fragments, `0x02` = final) |
| 2 | 2 | message id (LE uint16) |
| 4 | 2 | fragment index (LE uint16) |
| 6… | n | payload bytes |

Reassemble fragments sharing the same message id until a fragment with `final` is received. Max reassembled message: 2048 bytes.

Transport: write assembled bytes to **Command RX**; notifications on **Event TX** use the same framing.

## JSON message envelope

```json
{
  "v": 1,
  "type": "HELLO",
  "id": "msg-uuid-or-counter",
  "ts": 1710000000,
  "body": {}
}
```

### Message types

| type | Direction | Purpose |
|------|-----------|---------|
| `HELLO` | both | Device ID, app/fw version, protocol version |
| `AUTH` | both | Challenge / response ownership proof |
| `CAPABILITIES` | both | Feature flags |
| `STATE_VERSION` | both | Monotonic revision + last sync point |
| `STATE_SNAPSHOT` | both | Full state blob |
| `DELTA` | both | Partial changes since revision |
| `ACK` / `NACK` | both | Confirm or reject |
| `HEARTBEAT` | optional | App-level liveness |
| `UI_HINT` | Deskbot→App | LCD confirmation code / status |
| `FACTORY_RESET` | App→Deskbot | Clear ownership (authenticated) |
| `DISPLAY` | App→Deskbot | Notify / calendar / scenery / clock sync (auth required) |

### DISPLAY body

Authenticated session only. Ops:

```json
{ "op": "notify", "title": "Messages", "body": "Lunch at noon?", "mood": "curious", "ttl_ms": 8000 }
{ "op": "notify_clear" }
{ "op": "calendar", "title": "Standup", "when": "3:30p" }
{ "op": "calendar_clear" }
{ "op": "prompt", "speaker": "nova", "text": "Hello from phone" }
{ "op": "layout", "eyes": true, "clock": "center" }
```

`clock`: `off` | `top` | `center` | `bottom` | `left` | `right`. Layout is stored in NVS; scenery bitmap is stored on SPIFFS and restored on boot.

{ "op": "scenery", "w": 32, "h": 18, "fmt": "rgb565", "data": "<base64>" }
{ "op": "scenery_begin", "w": 160, "h": 86, "fmt": "rgb565" }
{ "op": "scenery_chunk", "off": 0, "data": "<base64 rgb565 bytes>" }
{ "op": "scenery_end" }
{ "op": "scenery_clear" }
```

Preferred: chunked `scenery_begin` / `scenery_chunk` / `scenery_end` at **160×86** (half LCD, ~27KB RGB565). Phone encodes photos with cover-crop + average downsample + Floyd–Steinberg dither so gradients still read as a photo. Desk upscales with a fast exact 2× blit. One-shot `scenery` remains for tiny payloads only.

### HELLO body

```json
{
  "device_id": "nova-a1b2c3d4",
  "role": "deskbot|app",
  "fw": "1.0.0",
  "app": "1.0.0",
  "protocol": 1,
  "model": "deskbot-c6-147"
}
```

### AUTH flow

1. Deskbot (or app) sends `AUTH` with `{ "op": "challenge", "nonce": "<hex32>" }`.
2. Peer responds `{ "op": "response", "nonce": "<same>", "mac": "<hmac-sha256-hex of nonce with ownership secret>" }`.
3. Verifier replies `ACK` or `NACK`.

First-time registration:

1. App writes Control Session `{ "op": "register", "owner_token": "<random 32B hex>", "confirm": "<4-digit code>" }`.
2. Deskbot accepts only if LCD confirmation code matches (or single nearby unit auto-confirm).
3. Deskbot stores owner token + device_id in NVS and marks registered.

### Device Info (Read)

JSON string:

```json
{
  "model": "deskbot-c6-147",
  "fw": "1.0.0",
  "protocol": 1,
  "device_id": "nova-a1b2c3d4",
  "registered": false,
  "capabilities": ["face", "clock", "sync_v1", "notify_v1", "calendar_v1", "scenery_v1"]
}
```

### State snapshot (v1)

```json
{
  "rev": 12,
  "expression": "happy",
  "ble_pip": true,
  "settings": {
    "brightness": 50,
    "quiet_hours": false
  }
}
```

## Advertising modes

| Mode | Behavior |
|------|----------|
| Unregistered | Advertise service UUID + setup-available flag; name `NOVA-Setup` |
| Registered offline | Advertise service UUID + registered flag + short device id; name `NOVA` |
| Post-disconnect burst | 20–40 ms interval for ~30 s, then 100–200 ms backoff |

## LCD status labels

| State | Label | Icon mood |
|-------|-------|-----------|
| Unregistered | Open app | curious |
| Confirm code | CODE 1234 | focused |
| Connecting | Connecting | thinking |
| Connected | Connected | happy (1–2s) |
| Syncing | Syncing | thinking |
| Connected normal | (face+clock) | tiny pip |
| Weak | (subtle pip) | — |
| Away | (face+clock) | disconnected pip |
| Returned | Welcome | happy flash |
| Recovery | Open app | worried |

## Security notes

- BLE advertised name is not identity.
- Ownership secret never written to Event TX in cleartext after registration.
- Privileged commands require authenticated session.
- Factory reset clears NVS ownership and returns to UNREGISTERED.
