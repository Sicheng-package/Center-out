# Introduction

This repository provides MATLAB-based code for a **center-out reaching task** that integrates both **unimanual (single-hand)** and **bimanual (two-hand)** paradigms into a **single unified framework**.

  - The **right-side computer** runs `R.m` (or `R3.m`), which acts as **TCP server + trial scheduler**, dynamically interleaving:
      - Bimanual trials (BI)
      - Left-only unimanual trials (UNI-L)
      - Right-only unimanual trials (UNI-R)
  - The **left-side computer** runs `L.m` (or `L3.m`) as a **TCP client**, sharing the same state machine, timing rules, and trial structure.

The task was designed for rhesus monkeys, initially using a mouse-controlled on-screen cursor (which can be replaced with USB joysticks in future versions) to perform center-out reaches toward 8 peripheral targets. The framework is suitable for electrophysiology experiments (e.g., Neuropixels), where precise timing and dual-hemisphere control are required.

-----

## Requirements

1.  **Input device**
      - Currently: standard mouse (cursor controlled via OS)
      - Optionally: USB-based joysticks (after mapping deflection to cursor position/velocity)
2.  **Two computers with MATLAB**
      - Tested version: MATLAB R2022a or later
      - Required toolboxes:
          - Data Acquisition Toolbox
          - Instrument Control Toolbox
3.  **NI DAQ hardware**
      - Example: NI USB-6009 or similar
      - Left computer: device name `Dev3`
      - Right computer: device name `Dev4`
      - Used for TTL signal output and alignment with neural recordings
      - **(New for L3/R3)**: Requires Digital Input on `Port1/Line3` for touch sensors.
4.  **Network connection**
      - Ethernet cable or LAN connection for TCP communication
      - Default server IP in `L.m`: `192.168.0.10`
      - Default TCP port in `R.m`: `30000`

-----

## To run this code

1.  **On the right-side computer (server / scheduler)**

      - Open MATLAB
      - Make sure the NI device (e.g., `Dev4`) is available
      - Run:
        ```matlab
        R   % (Or R2, R3 depending on version)
        ```

2.  **On the left-side computer (client)**

      - Open MATLAB
      - Edit `L.m` if necessary to set the correct `serverIP`
      - Make sure the NI device (e.g., `Dev3`) is available
      - Run:
        ```matlab
        L   % (Or L2, L3 depending on version)
        ```

3.  **Synchronization & task start**

      - Both sides first enter a **black-screen synchronization phase** (e.g., 10 s) using a simple TCP barrier.
      - After barrier synchronization, both screens display:
          - A yellow center target
          - 8 peripheral targets arranged on a circle
      - The right-side computer schedules bimanual / unimanual trials in a shuffled order and broadcasts trial metadata (mode + active side + direction) via TCP.

-----

## Parameters

Key behavioral parameters (defined in scripts):

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

-----

## Outputs

Both `L.m` and `R.m` save:

### 1\. Cursor trajectories (per-trial traces)

  - Left side:
      - Folder: `L/`
      - Files: `left<N>.xlsx`
  - Right side:
      - Folder: `R/`
      - Files: `right<N>.xlsx`

Each file contains a matrix with columns:

```text
[x, y, t]  % (L3/R3 adds a 4th column: touchStatus)
```

-----

## Patch: L2 / R2 (Updated Unimanual Logic)

A small patch has been added in the updated `L2.m` and `R2.m` scripts:

1.  **New helper function(s) for the holding stage**
    The holding-stage logic has been refactored into dedicated helper function(s) to make the code easier to read and to keep the state machine for center/target hold checks in one place.

2.  **Unimanual holding rule updated**

      - In **unimanual trials (UNI-L / UNI-R)**, **only the active hand** is required to acquire and hold the center / target for the specified `centerHoldDuration` and `targetHoldDuration`.
      - The **inactive hand** is no longer required to perform a full hold in the center/target. Instead, it must simply remain **relatively still**:
          - Its cursor displacement must stay **below a “no-move” / holding threshold**.
          - If the inactive hand shows a clear movement exceeding this threshold, the trial is treated as a **failure** (just like a break of hold in the active hand).

    This update makes unimanual tasks less constrained for the non-moving hand while still enforcing that the “inactive” limb does not make large movements during the hold period.

-----

## Patch: L4 / R4 (Touch Detection & Interactive Mode)

The `L4.m` and `R4.m` scripts introduce significant hardware integration and usability improvements:

1.  **Interactive Mode Selection (Server-Side)**

      - Upon running `R4`, a GUI dialog box now appears requesting the operator to select the session mode:
          - *Mix (Bi/L/R)*
          - *Bi-Manual Only*
          - *Uni-Left Only*
          - *Uni-Right Only*
      - This allows for targeted training sessions (e.g., forcing only left-hand trials) without modifying the code.

2.  **Capacitive Touch Integration (Strict Holding)**

      - **Hardware Requirement:** A digital input signal (TTL) from a touch sensor is required on `Port1/Line3` of the NI DAQ.
      - **Strict Hold Logic:** A valid "Center Hold" now requires **simultaneous** satisfaction of two conditions:
        1.  Cursor is strictly inside the center circle.
        2.  Touch sensor reads `1` (Hand is physically gripping the handle).
      - **Failure Mode:** If the subject releases the handle (Signal `0`) or exits the circle at any point during the hold duration, the trial is **immediately** marked as `Fail` and the task resets.
  
<img width="1280" height="1707" alt="image" src="https://github.com/user-attachments/assets/9bae189c-22a3-4265-90cf-44513f531910" />

3.  **Performance Optimization**

      - **Decimated Sampling:** To prevent cursor lag/stuttering during high-frequency loops, DAQ reading is performed at a decimated rate (e.g., every 15ms) rather than every frame.
      - **Phase-Dependent Sensing:** Touch detection is active *only* during the Center Hold phase to maximize performance during the reaching phase.
