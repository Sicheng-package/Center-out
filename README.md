# Introduction  

This repository provides MATLAB-based code for a **center-out reaching task** that integrates both **unimanual (single-hand)** and **bimanual (two-hand)** paradigms into a **single unified framework**.  

- The **right-side computer** runs `R.m`, which acts as **TCP server + trial scheduler**, dynamically interleaving:
  - Bimanual trials (BI)
  - Left-only unimanual trials (UNI-L)
  - Right-only unimanual trials (UNI-R)
- The **left-side computer** runs `L.m` as a **TCP client**, sharing the same state machine, timing rules, and trial structure.

The task was designed for rhesus monkeys, initially using a mouse-controlled on-screen cursor (which can be replaced with USB joysticks in future versions) to perform center-out reaches toward 8 peripheral targets. The framework is suitable for electrophysiology experiments (e.g., Neuropixels), where precise timing and dual-hemisphere control are required.

---

## Requirements  

1. **Input device**
   - Currently: standard mouse (cursor controlled via OS)
   - Optionally: USB-based joysticks (after mapping deflection to cursor position/velocity)
2. **Two computers with MATLAB**
   - Tested version: MATLAB R2022a or later
   - Required toolboxes:
     - Data Acquisition Toolbox
     - Instrument Control Toolbox
3. **NI DAQ hardware**
   - Example: NI USB-6009 or similar
   - Left computer: device name `Dev3`
   - Right computer: device name `Dev4`
   - Used for TTL signal output and alignment with neural recordings
4. **Network connection**
   - Ethernet cable or LAN connection for TCP communication
   - Default server IP in `L.m`: `192.168.0.10`
   - Default TCP port in `R.m`: `30000`

---

## To run this code  

1. **On the right-side computer (server / scheduler)**  
   - Open MATLAB  
   - Make sure the NI device (e.g., `Dev4`) is available  
   - Run:
     ```matlab
     R
     ```

2. **On the left-side computer (client)**  
   - Open MATLAB  
   - Edit `L.m` if necessary to set the correct `serverIP`  
   - Make sure the NI device (e.g., `Dev3`) is available  
   - Run:
     ```matlab
     L
     ```

3. **Synchronization & task start**  
   - Both sides first enter a **black-screen synchronization phase** (e.g., 10 s) using a simple TCP barrier.
   - After barrier synchronization, both screens display:
     - A yellow center target  
     - 8 peripheral targets arranged on a circle  
   - The right-side computer schedules bimanual / unimanual trials in a shuffled order and broadcasts trial metadata (mode + active side + direction) via TCP.

---

## Parameters  

Key behavioral parameters (defined in `L.m` and `R.m`):

- `centerHoldDuration`  
  Required center-hold duration (seconds) before the trial “leaves center” and a direction is assigned.

- `targetHoldDuration`  
  Required hold time inside the target (seconds) for a trial to be counted as successful.

- `FIRSTMOVE_DELTA`  
  Movement onset threshold (distance from center in normalized screen coordinates). When the cursor moves farther than this distance for a sufficient number of frames, the **first-move** is detected and a TTL is sent.

- `FIRSTMOVE_FRAMES`  
  Number of consecutive frames that the movement must exceed `FIRSTMOVE_DELTA` to be considered a valid first-move.

- `timeout`  
  Maximum trial duration after leaving the center (currently hard-coded as 8 seconds). If the subject fails to reach and hold the target within this time, the trial is marked as a failure.

- `circleDiameter` / `circleDiameter2` and `radii`  
  - `circleDiameter2`: size of the center target  
  - `circleDiameter`: size of the peripheral targets  
  - `radii`: distance of peripheral targets from the center  

- `trialMode` (internal)  
  - `1`: bimanual (BI)  
  - `2`: unimanual left (UNI-L)  
  - `3`: unimanual right (UNI-R)  

The right-side script (`R.m`) maintains three separate direction queues (`remainingBI`, `remainingUniL`, `remainingUniR`) and shuffles a base pattern of modes (`bi`, `uniL`, `uniR`) to provide **integrated, interleaved** single-hand + bimanual blocks within one continuous session.

---

## Outputs  

Both `L.m` and `R.m` save:

### 1. Cursor trajectories (per-trial traces)  

- Left side:
  - Folder: `L/`
  - Files: `left<N>.xlsx`
- Right side:
  - Folder: `R/`
  - Files: `right<N>.xlsx`

Each file contains a matrix with columns:

```text
[x, y, t]

## Patch: L2 / R2 scripts (updated unimanual holding logic)

A small patch has been added in the updated `L2.m` and `R2.m` scripts:

1. **New helper function(s) for the holding stage**  
   The holding-stage logic has been refactored into dedicated helper function(s) to make the code easier to read and to keep the state machine for center/target hold checks in one place.

2. **Unimanual holding rule updated**

   - In **unimanual trials (UNI-L / UNI-R)**, **only the active hand** is required to acquire and hold the center / target for the specified `centerHoldDuration` and `targetHoldDuration`.  
   - The **inactive hand** is no longer required to perform a full hold in the center/target. Instead, it must simply remain **relatively still**:
     - Its cursor displacement must stay **below a “no-move” / holding threshold**.
     - If the inactive hand shows a clear movement exceeding this threshold, the trial is treated as a **failure** (just like a break of hold in the active hand).

   This update makes unimanual tasks less constrained for the non-moving hand while still enforcing that the “inactive” limb does not make large movements during the hold period.


