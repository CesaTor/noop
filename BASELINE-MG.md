# Known-good baseline: WHOOP MG · fw 50.39.1.0

Date: 2026-09-04. Strap: WHOOP MG (variant attested `MG`). Phone: Android, NOOP debug 11.1.1.
Mac app deliberately idle during captures (strap dumps history to the first device that asks).

## Firmware (unpinned — see note)
- `50.39.1.0` (DIS read, stamped into `ecgSession` rows). No extraction path exists; the only
  protection is declining updates in the official WHOOP app. NOOP never flashes firmware.

## Verified behavior on this firmware
- History offload (Android, main device): HISTORY_COMPLETE, 2956 rows/night typical;
  `banked 1123 v18 aux rows (0 with @82 signal)` — flat-zero @82 shape, subscription gate suspected.
- ECG capture: signal-armed window opens on first waveform, verdict renders, auto-stop fires.
- Coach model list vs LiteLLM proxy: Bearer auth, reachable `/models`, lists on Refresh.

## Settings that matter (do not flip casually)
- SpO₂ candidate display: ON (Settings → Advanced → Diagnostics → "Blood Oxygen: strap estimate").
- ECG listen + Test Centre → Connection: ON (probe runs need both).
- `.noopbak` export of this state: kept off-phone, dated 2026-09-04.

## If behavior drifts
Re-run, in order: history offload (aux line), feature-flag probe, device-config probe. Diff the
three outputs against this file before touching any setting. A changed verdict on unchanged
settings means the ground moved (usually a strap firmware update), not a app regression.
