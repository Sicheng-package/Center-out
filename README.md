Introduction
This repository provides MATLAB-based code for a center-out reaching task that integrates both unimanual (single-hand) and bimanual (two-hand) paradigms.

The right-side computer runs bimanual_R_touch.m (Server) or unimanual_R_touch.m (Independent).

The left-side computer runs bimanual_L_touch.m (Client) or unimanual_L_touch.m (Independent).

The bimanual scripts utilize a TCP server/client architecture to synchronize trial starts and compare performance timestamps (TTLs) between hands.

The framework is designed for high-precision motor control experiments requiring integration with NI-DAQ hardware for capacitive touch sensing and neural recording alignment.

Requirements
Input Device

Standard mouse or cursor-controlled device.

The system uses Java Robot to automatically reset the mouse position to the center of the screen at the start of each trial.

Two Computers with MATLAB

Required for bimanual synchronization via TCP/IP.

Default server IP for the left client is 192.168.0.10.

Default TCP port is 30000.

NI DAQ Hardware

Left computer: device name Dev3.

Right computer: device name Dev4.

Digital Input: Requires a touch sensor signal on port1/line3.

Digital Output: Sends TTL pulses on port0/line0:4 for movement onset, target acquisition, and trial synchronization.

To run this code
On the right-side computer (Server for Bimanual)

Run bimanual_R_touch(goalSuccesses) or unimanual_R_touch(goalSuccesses).

The bimanual script will wait for a TCP connection from the client.

On the left-side computer (Client for Bimanual)

Run bimanual_L_touch(goalSuccesses) or unimanual_L_touch(goalSuccesses).

The bimanual client will attempt to connect to the server IP.

Synchronization & Task Start

Both sides enter a black-screen synchronization phase (e.g., 10 seconds).

In bimanual mode, a TCP barrier ensures both computers are "READY" before the black screen ends and "DONE" before the task begins.

The task starts with a yellow center target and 8 possible peripheral targets arranged in a circle.

Parameters
Key behavioral parameters defined in the scripts:

centerHoldDuration: Required time (1.0s) the subject must touch and hold the center target.

targetHoldDuration: Required time (1.0s) the subject must touch and hold the peripheral target.

firstMovementThreshold: Movement onset threshold (0.05 units). When the cursor moves beyond this distance, a "First Move" TTL is triggered.

TOUCH_FRAMES: Number of consecutive frames (5) the touch signal must be stable to be registered.

timeout: Maximum trial duration (8 seconds) to reach the target after leaving the center.

circleDiameter / circleDiameter2: Size of peripheral (0.1–0.15) and center (0.1) targets.

radii: Distance of peripheral targets from the center (0.25).

Outputs
All scripts save data into specific folders:

1. Cursor Trajectories
Left side: Folder S1L (Unimanual) or S1_L (Bimanual); files named left<N>.xlsx.

Right side: Folder S1R (Unimanual) or S1_R (Bimanual); files named right<N>.xlsx.

Trajectory data columns: [x, y, t].

2. Summary Statistics
Files: Summary_Data.xlsx (Unimanual) or Summary_Data_R1.xlsx / Summary_Data_L1.xlsx (Bimanual).

Data includes: Trial number, Target ID, Duration, First Move Time, Success/Fail Status, and TTL timestamps.

Bimanual summaries also include TTL_StartDiff and TTL_EndDiff to measure synchronization between hands.

Patch: Touch Detection & Synchronized Holding
This version of the code implements advanced Capacitive Touch Integration:

Strict Hold Logic

A valid hold requires the cursor to be inside the target AND the touch sensor (DAQ port1/line3) to be active.

If the touch is lost (Signal 0) or the cursor leaves the area during the hold duration, the trial is immediately failed.

Debounced Sensing

The debounceTouch function prevents accidental failures due to momentary signal noise by requiring 5 consecutive frames of the same touch state.

Bimanual Temporal Alignment

For bimanual success, the difference between left and right "First Move" (TTL1) and "Target Reach" (TTL2) must be within a threshold (0.5s).

If the hands are out of sync, the trial is recorded as a failure.
<img width="1280" height="1707" alt="image" src="https://github.com/user-attachments/assets/9bae189c-22a3-4265-90cf-44513f531910" />

