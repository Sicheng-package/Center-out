## Introduction

This repository provides MATLAB-based code for a **center-out reaching task** that integrates both **unimanual (single-hand)** and **bimanual (two-hand)** paradigms into a synchronized experimental framework.

* The **right-side computer** runs `bimanual_R_touch.m` as the **TCP server** or `unimanual_R_touch.m` for independent tasks.
* The **left-side computer** runs `bimanual_L_touch.m` as a **TCP client** or `unimanual_L_touch.m` for independent tasks.
* The system is designed for high-precision motor control studies, utilizing a state machine that handles center-holding, target-reaching, and real-time touch sensor validation.

---

## Requirements

1. **Input Device**
* Standard mouse (cursor position is mapped to the task workspace).
* Automated cursor reset to the center is handled via the Java `Robot` class.


2. **Two Computers with MATLAB**
* Required for bimanual synchronization via TCP/IP communication.
* The framework uses the `Instrument Control Toolbox` for TCP connectivity.


3. **NI DAQ Hardware**
* **Left computer**: NI device name must be configured as `Dev3`.
* **Right computer**: NI device name must be configured as `Dev4`.
* **Digital Input**: Requires a touch sensor signal on `port1/line3`.
* **Digital Output**: Sends TTL pulses on `port0/line0:4` for neural alignment.


4. **Network Connection**
* Default server IP in `bimanual_L_touch.m`: `192.168.0.10`.
* Default TCP port: `30000`.



---

## To run this code

1. **On the right-side computer (Server / Scheduler)**
* Open MATLAB and ensure the NI device (`Dev4`) is connected.
* Run the desired script: `bimanual_R_touch()` or `unimanual_R_touch()`.


2. **On the left-side computer (Client)**
* Ensure the NI device (`Dev3`) is connected and the IP address matches the server.
* Run the desired script: `bimanual_L_touch()` or `unimanual_L_touch()`.


3. **Synchronization & Task Start**
* Both systems enter a **black-screen synchronization phase** (10 seconds) using a TCP barrier to ensure both sides are ready.
* The task automatically initializes the workspace with a yellow center target and peripheral targets after the synchronization period.



---

## Parameters

Key behavioral and timing parameters (hard-coded in scripts):

* `centerHoldDuration`: Subject must maintain position and touch in the center for **1.0 second**.
* `targetHoldDuration`: Subject must maintain position and touch in the target for **1.0 second**.
* `firstMovementThreshold`: Displacement of **0.05 units** required to trigger the "First Move" TTL.
* `timeout`: Maximum trial duration is set to **8 seconds**.
* `circleDiameter2`: Size of the center target (**0.1**).
* `circleDiameter`: Size of peripheral targets (**0.1** for unimanual, **0.15** for bimanual).
* `radii`: Distance of peripheral targets from the center (**0.25**).
* `TOUCH_FRAMES`: Number of consecutive samples (**5**) required for a stable touch state.

---

## Outputs

Both systems save two types of experimental data:

### 1. Cursor Trajectories

* **Left side**: Saved in folder `S1L` (Unimanual) or `S1_L` (Bimanual) as `left<Trial#>.xlsx`.
* **Right side**: Saved in folder `S1R` (Unimanual) or `S1_R` (Bimanual) as `right<Trial#>.xlsx`.
* File structure: `[X-coordinate, Y-coordinate, Timestamp]`.

### 2. Summary Data

* **Unimanual**: `Summary_Data.xlsx`.
* **Bimanual**: `Summary_Data_L1.xlsx` and `Summary_Data_R1.xlsx`.
* Columns include: `Trial`, `Target`, `Dur`, `FirstMoveTime`, `Status`, `TTL_FirstMove`, `TTL_End`, and `CenterHoldStartTime`.

---

## Patch: Touch Detection & Synchronized Holding

This update focuses on integrating physical feedback into the motion state machine:

1. **Capacitive Touch Integration**
* The task requires **simultaneous** presence inside the target and a valid digital high signal from the touch sensor.
* If the touch signal is lost at any point during the hold period, the trial is immediately terminated as a failure.


2. **Bimanual Temporal Constraints**
* In bimanual mode, the system compares the timing between the left and right hands.
* The trial is only successful if the temporal difference for both the movement onset (`ttlStartDiff`) and target acquisition (`ttlEndDiff`) is within a **0.5-second threshold**.


3. **Signal Debouncing**
* A `debounceTouch` function is implemented to filter electrical noise from the touch sensors, requiring the signal to be stable for 5 consecutive frames before updating the logic state.


<img width="1280" height="1707" alt="image" src="https://github.com/user-attachments/assets/9bae189c-22a3-4265-90cf-44513f531910" />

