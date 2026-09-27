# QA Matrix — BLE Companion (SOW §18–§19)

## Acceptance checklist

- [ ] New user registers from the app without opening Bluetooth Settings
- [ ] Discovery shows only Deskbot service UUID matches
- [ ] Reopening the app does not require setup again
- [ ] Deskbot power-cycle reconnects without re-registration
- [ ] Walk out of range → quiet disconnect; return → auto session restore
- [ ] Settings/state changes while apart reconcile after reconnect
- [ ] No Connected/Disconnected flicker from RSSI wobble
- [ ] Second nearby Deskbot cannot steal registration via stronger RSSI
- [ ] 1.47" states readable; no multi-step nav on deskbot
- [ ] Failure states have deterministic recovery paths

## Test areas

| Area | Cases |
|------|--------|
| First setup | Single unit, multiple nearby + code, wrong code, interrupted setup, permission denial |
| Reconnect | Leave/return room, deskbot restart, app restart, phone restart, RF interference |
| Background | iOS background limits, Android Doze/vendor, foreground recovery after force-quit |
| RSSI | Desk distance, same room, body block, wall, hysteresis |
| Sync | No changes, app-only, deskbot-only, conflict, large payload, interrupted |
| Security | Unknown phone, cloned name, stale credential, factory reset, remove deskbot |
| UI | All LCD states on hardware; font truncation; animation feel |

## Diagnostics

- Firmware log tags: `ble`, `sync`, `sm`, `own`, `face`
- App: `debugPrint` on notify parse errors; connection phase in UI status chip

## Field notes

Record phone model/OS, RSSI at desk, and time-to-reconnect after return.
