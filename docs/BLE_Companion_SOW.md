# Deskbot BLE Companion SOW

Imported from Deskbot_BLE_Companion_Feature_Addition_SOW.docx


DESKBOT
BLE Companion ConnectivityFeature Addition & SOW
For an ESP32-based deskbot with a 1.47-inch display
Product Intent
Create a phone-to-deskbot experience that feels automatic: the user opens the app once, discovers and registers the deskbot inside the app, and does not need to manually pair it through Bluetooth Settings. After registration, the deskbot should reconnect and synchronize automatically whenever the user returns within usable BLE range.

Document Type
Feature Addition / Statement of Work
Primary Device
ESP32-based deskbot
Deskbot Display
1.47-inch screen (UI designed resolution-agnostic until panel pixels are confirmed)
Connectivity
Bluetooth Low Energy (BLE)
Platforms
iOS and Android companion application

1. Executive Summary
This feature adds a persistent BLE relationship between the Deskbot and its mobile app. The user performs setup entirely inside the app, without first visiting the phone's Bluetooth Settings. The app identifies the correct deskbot, registers ownership, connects, authenticates, stores the device identity, and starts data synchronization. On later use, the system attempts reconnection automatically whenever the registered deskbot is reachable.
BLE signal strength (RSSI) may be used as a supporting proximity signal for nearby/away behaviors and UI, but it will not be treated as exact distance. Reconnection will be driven by BLE connection state and remembered-device logic, with RSSI smoothing and hysteresis used only where proximity context adds value.
Normal returning-user path
App opens
Find registered Deskbot
Connect automatically
Authenticate
Delta sync
Ready

Core UX Rule
Bluetooth Settings should not be part of normal onboarding. The only unavoidable platform-level steps are operating-system permission prompts and any security confirmation required by the selected BLE security mode.

2. Goals and Product Outcomes
One-time in-app setup with automatic discovery of the Deskbot.
No requirement for the user to manually locate the Deskbot in Bluetooth Settings.
Automatic reconnection after the user walks away and later returns.
Fast recovery from temporary signal loss without presenting repeated setup dialogs.
A minimal 1.47-inch Deskbot UI that communicates state without becoming a settings-heavy interface.
Secure device ownership so the app does not silently attach to a nearby stranger's Deskbot.
Reliable bidirectional synchronization of device state and app data.
Clear recovery paths for reset, phone replacement, revoked ownership, and multiple nearby Deskbots.
3. Scope of Feature Addition
Workstream
Included Scope
Deskbot BLE firmware
Advertising, custom GATT service, registration state, authentication, reconnect behavior, RSSI support, sync messaging, error/recovery states.
Mobile BLE layer
Discovery, service filtering, remembered-device storage, connection state machine, auto-reconnect, subscriptions, read/write transport, platform lifecycle handling.
Mobile setup UX
First-launch discovery, found-device confirmation, ownership confirmation, connected state, recovery and remove/reset flows.
1.47-inch Deskbot UX
Setup, connecting, connected, away/offline, syncing and recovery states with short text and icon-first communication.
Proximity behavior
Smoothed RSSI-based near/weak signal classification where useful; no promise of precise distance.
Data synchronization
Handshake, current-state snapshot, delta sync, acknowledgements, versioning and resumption after reconnect.
QA and acceptance
Connection, reconnect, multi-device, power-cycle, app restart, background, permission and weak-signal scenarios.

4. UX Principles for a 1.47-inch Deskbot Screen
The Deskbot screen should behave as a status surface, not as a miniature phone UI. The phone handles configuration; the Deskbot communicates only what the user needs at that moment.
Principle
Implementation
Icon first
Use a large central state icon/animation with one short label beneath it.
One action at a time
Avoid menus during setup. Show only the current required action.
Transient confirmations
“Connected” and “Synced” appear briefly, then the normal Deskbot face/home returns.
Quiet disconnection
When the phone leaves range, show a subtle offline/BLE indicator rather than a blocking error.
Automatic recovery
When the phone returns, show a short reconnect/sync animation; do not ask the user to reconnect manually.
Readable at desk distance
Large iconography, high contrast, very short text; exact typography scales to the final panel resolution.

5. Deskbot Screen States
State
Suggested 1.47-inch Display
Behavior
Unregistered
Deskbot face + small phone/BLE setup icon; “Open app to set up”
Deskbot advertises as available for setup.
Found / awaiting confirmation
Pairing/link icon + short setup code or confirmation symbol
Used only during first ownership registration.
Connecting
Small animated link/BLE indicator; “Connecting”
Short-lived, non-blocking state.
Connected
Check/link animation; “Connected” for ~1-2 seconds
Immediately transitions back to normal Deskbot UI.
Syncing
Circular sync indicator; optional percentage only for long sync
Shown only if sync is noticeable.
Normal connected
Primary Deskbot face/home + tiny connected indicator
Default daily state.
Weak / moving away
Optional subtle weak-signal icon
Do not alarm user; no modal UI.
Phone away
Primary Deskbot face/home + small disconnected indicator
Deskbot remains usable for local functions.
Phone returned
Brief reconnect indicator, then sync
Fully automatic.
Recovery required
Short code/icon + “Open app”
Only for ownership mismatch, reset, or unrecoverable auth state.

6. First-Time Setup Flow
First-time experience - no Bluetooth Settings detour
Open app
Grant Bluetooth permission
App scans for Deskbot service
Deskbot found
User confirms
Register ownership
Connect + sync

6.1 Discovery
The app scans only for the Deskbot's known BLE service UUID and/or manufacturer data. Generic nearby Bluetooth devices are ignored. The user should see a product-specific “Looking for your Deskbot…” screen rather than a raw Bluetooth device list.
6.2 Correct-device confirmation
If exactly one unregistered Deskbot is strongly visible, the app can present it immediately. If multiple compatible units are nearby, require the user to confirm the specific unit using a short code displayed on the Deskbot. A QR code may be offered only if the final 1.47-inch panel resolution and camera scan testing make it reliable.
6.3 Ownership registration
On confirmation, the app and Deskbot exchange an ownership/setup secret and assign a stable logical Device ID. The Deskbot records that it is registered. The phone stores the corresponding device identity and credentials securely.
6.4 Connection
The app initiates the BLE GATT connection itself. Manual pre-pairing in Bluetooth Settings is not part of the intended workflow.
6.5 Initial synchronization
After authentication, the app and Deskbot exchange protocol version, capabilities, clock/time information, settings and the current state snapshot. The UI transitions to Ready only after the required initial sync succeeds.
7. Daily Auto-Connect and Return-to-Range Flow
Walk-away and return sequence
Previously registered
Phone/Deskbot separated
BLE link drops
Deskbot keeps advertising
User returns
Known device reconnects
Authenticate + delta sync
Normal UI

Expected behavior: the user should not press a Connect button during normal daily use. If the Deskbot was previously registered and both devices have Bluetooth available, the system should attempt to restore the connection automatically.
Stage
Deskbot
Mobile App
Connected
Normal UI, BLE connected flag set.
Maintains GATT connection and subscriptions.
User moves away
May see RSSI weaken; no immediate user-facing change required.
Treats RSSI as advisory only.
Link lost
Returns to advertising and marks phone unavailable.
Records disconnect and maintains reconnect intent for the registered Deskbot.
Away
Local Deskbot features continue.
No repeated alerts; app waits for reconnect opportunity.
User returns
Advertising is discoverable/reconnectable.
System/app identifies the remembered Deskbot and reconnects.
Reconnected
Authenticates and resumes session.
Resubscribes to characteristics and performs delta sync.
Ready
Normal connected UI.
Shows connected status without requiring user interaction.

8. Nearby Detection and RSSI Strategy
Bluetooth RSSI can indicate relative signal strength, so it is useful for “nearby / weak / away” behavior. It is not a reliable distance measurement. Walls, the user's body, antenna orientation, desk materials and radio interference can change RSSI substantially even when physical distance is unchanged.
Requirement
Recommended Behavior
Reconnect trigger
Use registered-device BLE availability / connection state, not a single RSSI threshold.
Nearby status
Use a rolling/filtered RSSI value (for example, median or exponential moving average) over several samples.
Hysteresis
Use different enter/exit thresholds and minimum dwell time so UI does not oscillate between Near and Away.
Calibration
Tune thresholds using the production enclosure, antenna placement and expected room layout.
Connected signal
Either side may read connected-link RSSI where the stack/platform permits; use it only for signal-quality UX.
Disconnected discovery
Advertisement RSSI can help rank multiple candidate Deskbots during setup and detect reappearance.
Exact distance
Out of scope for RSSI. If true ranging is needed later, evaluate UWB or other ranging-capable hardware.

Recommended proximity state model
Use broad semantic states such as STRONG / NEARBY / WEAK / NOT_CONNECTED. Thresholds should remain configurable and should be validated on the final hardware rather than hard-coded from generic dBm values.

9. Connection State Machine
State
Entry Condition
Primary Actions
Exit
UNREGISTERED
No owner credential stored
Advertise setup service; show setup UI
Registration approved
REGISTERED_OFFLINE
Owner exists; no active link
Advertise reconnect identity; wait for known phone
Connection initiated
CONNECTING
BLE connection attempt active
Show subtle linking state; apply timeout/retry policy
Connected or backoff
AUTHENTICATING
GATT connected
Challenge/response; verify owner/session
Verified or reject
SYNCING
Authenticated
Exchange versions; request/send state deltas; ack critical messages
Sync complete
CONNECTED
Session healthy
Normal data transfer; heartbeats only if required
Link loss / auth failure
RECONNECTING
Unexpected link loss
Keep reconnect intent; advertise appropriately
Connection restored or idle backoff
RECOVERY
Credential mismatch / reset / incompatible protocol
Require app-guided recovery
Recovered / factory reset

10. BLE Technical Architecture
Recommended topology: the phone acts as the BLE Central/GATT Client and the ESP32 Deskbot acts as the BLE Peripheral/GATT Server.
GATT Element
Purpose
Properties
Deskbot Service
Single product service used for discovery and capability detection.
Primary service UUID
Command RX
App sends commands, settings, sync requests and acknowledgements to Deskbot.
Write / Write Without Response as appropriate
Event TX
Deskbot sends events, state changes, telemetry and acknowledgements to app.
Notify
Device Info
Model, firmware, protocol version, logical Device ID and capabilities.
Read
Control / Session
Registration/authentication/session negotiation.
Read / Write / Notify
Optional OTA
Firmware metadata and update transport if BLE OTA is included later.
Separate secured service recommended

ESP32 implementation recommendation: use ESP-IDF with the NimBLE host when practical for a compact BLE implementation. Keep product protocol logic independent of the BLE stack so transport details can evolve without rewriting application behavior.
11. Advertising and Reconnect Behavior
When unregistered, advertise the setup service and an anonymous/product-safe identifier sufficient for the app to recognize a Deskbot.
When registered but disconnected, remain reconnectable and advertise only the minimum information necessary to identify the known product/session safely.
After an unexpected disconnect, use a faster advertising cadence initially for quick recovery, then reduce advertising frequency if the phone remains away. Exact values should be tuned against power and latency targets.
If the Deskbot is mains/USB powered, reconnect responsiveness can be prioritized more aggressively than for a battery-only wearable.
The mobile app should maintain reconnect intent for the registered Deskbot and restore characteristic subscriptions after every successful reconnection.
12. Data Synchronization Model
A reconnect should not blindly resend everything. The protocol should determine what changed while the devices were separated and synchronize only the required state.
Message/Concept
Purpose
HELLO
Exchange Device ID, app version, firmware version and protocol version.
AUTH
Prove ownership/session authenticity.
CAPABILITIES
Declare supported features so app and firmware can evolve independently.
STATE_VERSION
Compare monotonic state revision / last-known sync point.
STATE_SNAPSHOT
Transfer complete current state when versions diverge significantly or first setup occurs.
DELTA
Transfer only changed settings/events after a normal reconnect.
ACK / NACK
Confirm critical writes and identify rejected/invalid data.
HEARTBEAT
Optional; use only if application-level liveness is required beyond BLE link state.

Payload format: JSON is convenient for prototyping, but a compact binary format such as CBOR or a small versioned binary schema is recommended for production BLE traffic. Fragmentation/reassembly must be defined for payloads larger than the negotiated ATT payload.
13. Device Ownership and Security
Do not treat the BLE device name as proof of identity.
Generate a unique logical Device ID and per-device setup secret during manufacturing or first provisioning.
Require explicit first-time ownership confirmation when a new Deskbot is registered.
Store long-lived secrets using the platform secure storage/keychain mechanisms on the phone and protected storage on ESP32 where available.
Use challenge/response or session-key authentication so a nearby device cannot impersonate the registered Deskbot using only its advertised name/UUID.
Support “Remove Deskbot” in the mobile app and a deliberate Deskbot factory-reset procedure that clears ownership credentials.
If OS-level BLE bonding is enabled for security, initiate it as part of the in-app workflow; do not instruct the user to pre-pair in Bluetooth Settings.
14. Mobile Application UX
Screen / State
UX
Welcome
Explain that the app will find the Deskbot automatically. Primary CTA: “Find my Deskbot”. Auto-start scanning after Bluetooth permission if product design prefers fewer taps.
Searching
Product animation + “Looking for your Deskbot…”; no generic Bluetooth device list.
Deskbot found
Show Deskbot name/visual and confirmation code if needed. CTA: “Set up”.
Registering
Progress state: “Linking your Deskbot…”; handle permission/security prompts in context.
Connected
Short success state, then main dashboard.
Normal dashboard
Connection indicator should be informative but not dominant.
Deskbot away
Non-blocking “Deskbot offline / will reconnect automatically” state.
Reconnecting
Silent or subtle progress. Avoid repeated notifications.
Recovery
Clear actions: Try again, Bluetooth check, Restart Deskbot, Re-register / Remove Deskbot when truly necessary.

15. iOS and Android Platform Behavior
Platform
Implementation Notes
iOS
Use Core Bluetooth. The app can scan for the Deskbot service and connect directly, so manual Bluetooth Settings pairing is not required for the normal BLE GATT workflow. Store the known peripheral identity and use Core Bluetooth reconnection/restoration capabilities where applicable. Apple provides an auto-reconnect connection option for a connected peripheral after the BLE link drops. Background behavior must still follow iOS lifecycle rules, and force-quitting the app can limit what the app can do until relaunched.
Android
Use Android BLE GATT APIs for the data connection. Android association/presence APIs may be used internally to improve setup/background presence behavior, but the user experience remains entirely in the product app. Background execution and scan behavior must follow the Android version in use; test across supported OS versions and vendors.

Important platform expectation
“Automatic reconnect” means best-effort reconnection within the capabilities of iOS/Android, Bluetooth availability, app lifecycle, permissions and device power state. It should not be described as an unconditional guarantee when the user has force-quit the app, disabled Bluetooth, revoked permissions, or the operating system has restricted background execution.

16. Functional Requirements
ID
Requirement
BLE-01
The mobile app shall discover compatible Deskbots by service/manufacturer filtering without requiring the user to browse Bluetooth Settings.
BLE-02
The app shall store the identity of the registered Deskbot after successful first-time setup.
BLE-03
The Deskbot shall distinguish unregistered, registered-offline, connecting, connected and recovery states.
BLE-04
The app shall automatically attempt to reconnect to the registered Deskbot when it becomes reachable.
BLE-05
The Deskbot shall return to an advertising/reconnectable state after an unexpected disconnect.
BLE-06
After reconnect, the app shall restore required characteristic subscriptions before marking the session Ready.
BLE-07
App and Deskbot shall authenticate the registered relationship before accepting privileged commands.
BLE-08
The system shall support state resynchronization after a disconnect without requiring a new registration.
BLE-09
RSSI shall not be the sole source of truth for connected/disconnected state.
BLE-10
RSSI-driven UI states shall use smoothing/hysteresis and configurable thresholds.
BLE-11
The Deskbot screen shall show setup/reconnect status using short text and icon-led states appropriate for a 1.47-inch display.
BLE-12
The mobile app shall provide a user-controlled Remove Deskbot / re-registration workflow.
BLE-13
Deskbot factory reset shall clear stored ownership credentials and return the device to setup mode.
BLE-14
Multiple nearby Deskbots shall not cause silent registration to the wrong unit.
BLE-15
Normal reconnect after leaving and returning shall require no manual Connect action.

17. Required Edge Cases and Recovery Flows
Scenario
Required Result
Bluetooth disabled on phone
App explains Bluetooth is required; Deskbot remains available and resumes when Bluetooth returns.
Permission denied
App shows platform-appropriate permission recovery instructions; no false “device not found” message.
Deskbot power cycle
Deskbot boots as registered-offline and becomes reconnectable; no re-registration required.
Phone reboot
Known Deskbot remains registered; reconnect resumes when app/system conditions permit.
App terminated normally
On next launch, app retrieves remembered Deskbot and connects automatically.
App force-quit by user
Do not promise background reconnect until platform allows the app to run again; reconnect immediately on next launch.
User walks out of range
Link loss handled quietly; Deskbot does not forget ownership.
User returns
Automatic connection/authentication/delta sync without setup screen.
Several Deskbots nearby
Use registered Device ID and credentials; never reconnect to a different unit just because its RSSI is stronger.
Firmware/app protocol mismatch
Negotiate compatible version or present upgrade/recovery state; avoid undefined writes.
Deskbot factory reset
Old phone registration must fail safely; app offers re-register flow.
Phone replaced
New phone performs ownership transfer/re-registration according to product security policy.

18. Acceptance Criteria
A new user can register a powered Deskbot from inside the mobile app without first opening Bluetooth Settings.
The app identifies only supported Deskbot devices during its normal discovery experience.
After first registration, closing and reopening the app does not require setup again.
After the Deskbot power-cycles, it reconnects to the registered phone/app without re-registration when the platform permits.
Walking beyond BLE range causes a clean disconnect; returning to range restores the session automatically without a manual Connect button under normal supported lifecycle conditions.
After reconnect, settings/state changed while disconnected are reconciled correctly.
No repeated “Connected/Disconnected” UI flicker occurs when RSSI fluctuates near a threshold.
A second nearby Deskbot cannot take over the registered relationship based only on a stronger signal.
The 1.47-inch screen states remain readable and do not require multi-step navigation for connectivity.
All failure states provide a deterministic recovery path and do not require Bluetooth Settings except for OS-level troubleshooting when Bluetooth itself is disabled/restricted.
19. QA Test Matrix
Test Area
Minimum Coverage
First setup
Single Deskbot, multiple nearby Deskbots, wrong confirmation code, interrupted setup, permission denial.
Reconnect
Leave room / return; Deskbot restart; app restart; phone restart; temporary radio interference.
Background
Supported iOS background scenarios; Android background/Doze/vendor cases; app foreground recovery.
RSSI
Desk distance, same room, body obstruction, wall separation, noisy RF environment, threshold hysteresis.
Sync
No changes, app-only changes, Deskbot-only changes, conflicting changes, large state payload, interrupted sync.
Security
Unknown phone, cloned name/UUID, stale credential, reset Deskbot, removed Deskbot, replayed session data where applicable.
Compatibility
Supported iOS versions/devices and Android versions/device vendors defined by product release matrix.
UI
All Deskbot states on final 1.47-inch hardware, including brightness, font sizing, truncation and animation performance.

20. Implementation Deliverables
ESP32 BLE service and connection state machine integrated into Deskbot firmware.
Deskbot setup/connection/reconnect UI states for the 1.47-inch display.
iOS BLE service layer with discovery, known-device restore/reconnect, GATT transport and lifecycle handling.
Android BLE service layer with discovery, GATT transport and appropriate background/presence integration.
In-app first-time setup and registration screens.
Secure device identity/ownership storage and removal/reset workflow.
Versioned data synchronization protocol and message definitions.
RSSI sampling/filtering module and configurable proximity-state logic.
Connection diagnostics/logging sufficient for field troubleshooting.
QA checklist/test cases covering the acceptance criteria in this SOW.
21. Out of Scope / Separate Feature Items
Exact physical-distance measurement from BLE RSSI.
Apple Watch-level private/system integration or behavior reserved for Apple hardware/platform services.
Continuous guaranteed background execution when the user has force-quit the mobile app or revoked required permissions.
High-bandwidth media streaming over BLE.
Cloud account sync, remote access over the internet or multi-user sharing unless added as a separate feature.
BLE OTA firmware update unless explicitly added to implementation scope.
Wi-Fi provisioning or Wi-Fi data transport unless added as a separate feature.
UWB-based precise ranging/proximity unless the hardware is changed to support it.
22. Recommended Implementation Sequence
Phase
Focus
Exit Condition
1. BLE foundation
ESP32 advertising/GATT + app scan/connect + basic read/write/notify.
Stable foreground connection on iOS/Android.
2. Registration/security
Device identity, confirmation and stored ownership.
Correct unit can be registered and unauthorized unit rejected.
3. Reconnect lifecycle
Disconnect handling, reconnect intent, subscription restore.
Walk-away/return works repeatedly.
4. Sync protocol
Handshake, state versioning, delta/snapshot sync.
State is consistent after reconnect/power cycle.
5. Proximity UX
RSSI filtering/hysteresis and subtle near/weak UI.
No signal-state flicker in real-world tests.
6. 1.47-inch polish
Final icons, animations, timing and recovery screens.
Screen states readable on production display.
7. Hardening
Background behavior, edge cases, logs, soak tests.
Acceptance criteria and release test matrix pass.

Effort note: engineering hours are intentionally not fixed in this SOW because they depend on the current mobile codebase, selected ESP32 framework, existing protocol/UI architecture, security requirements and supported OS versions. These should be estimated after a short implementation spike confirms the production hardware and app stack.
23. Optional Future Enhancements
Deskbot-aware “Welcome back” animation when a prolonged away period ends.
Presence-driven local automation, such as changing Deskbot behavior when the registered phone is nearby.
BLE OTA firmware update.
Wi-Fi credential handoff from phone to Deskbot after secure BLE registration.
Multiple authorized phones / household users.
Cloud-assisted ownership transfer and backup.
UWB or other precise ranging for true distance-aware interactions.
24. Technical Reference Notes
The architecture in this SOW is aligned with the current platform capabilities documented by Apple, Google/Android and Espressif. Key references:
Apple Core Bluetooth - Peripheral Connection Options
Apple - CBConnectPeripheralOptionEnableAutoReconnect
Apple Core Bluetooth Framework
Android - Companion device pairing (optional OS integration under the app UX)
Android - CompanionDeviceManager presence APIs
Espressif - ESP BLE FAQ / RSSI APIs
Espressif - NimBLE-based Host APIs
Final Product Behavior
First time: open app -> Deskbot is discovered -> user confirms the correct unit -> app registers and connects -> sync completes. Daily use: the connection is automatic. When the user leaves BLE range, the Deskbot remains registered. When the user returns, the remembered Deskbot reconnects, authenticates, restores subscriptions and synchronizes changes without sending the user through setup again.

