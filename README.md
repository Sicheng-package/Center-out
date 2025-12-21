This is a comprehensive and professional README designed to showcase your motor control framework. It integrates your technical requirements with the recent logic updates (Patches L2–L4) to provide a clear, high-level overview for researchers.

---

# Motor Control Reach-to-Touch Framework (MATLAB)

This repository provides a unified MATLAB-based framework for **center-out reaching tasks**. It is designed for behavioral neuroscience and electrophysiology (e.g., Neuropixels), supporting interleaved **Unimanual (L/R)** and **Bimanual** paradigms with millisecond-precision timing.

## System Architecture

The framework operates on a **Server-Client** model via TCP/IP to ensure perfect synchronization between two separate computers controlling the left and right workspaces.

| Component | Role | Logic Script | Primary Responsibility |
| --- | --- | --- | --- |
| **Right Computer** | **Server** | `R4_touch.m` | Trial scheduler, TCP server, mode selection GUI. |
| **Left Computer** | **Client** | `L4_touch.m` | TCP client, follows server state machine. |

---

## Key Features

* **Integrated Trial Interleaving**: Dynamically switch between Bimanual (BI), Left-only (UNI-L), and Right-only (UNI-R) trials within a single session.
* **Capacitive Touch Integration**: Supports hardware-level "Strict Holding" via NI-DAQ digital input. Trials require both cursor positioning and physical contact (handle grip).
* **Sophisticated Hold Logic**:
* **Active Hand**: Must maintain center/target hold for a set duration.
* **Inactive Hand (UNI trials)**: Refined "No-Move" rule—the inactive limb must remain relatively still below a threshold, or the trial fails.


* **High-Frequency Data Logging**: Records  coordinates, time (), and touch status at high sampling rates to `.xlsx` trace files.
* **Automated Cursor Reset**: Uses the Java `Robot` class to ensure the starting position is identical for every trial.

---

## Hardware & Requirements

### 1. Requirements

* **MATLAB**: R2022a or later.
* **Toolboxes**: Data Acquisition Toolbox, Instrument Control Toolbox.
* **NI-DAQ Hardware**: (e.g., USB-6009).
* **Input**: Port1/Line3 for Touch Sensors.
* **Output**: Digital lines for TTL alignment with neural recording systems.



### 2. Networking

* **Connection**: Standard LAN/Ethernet.
* **Default Configuration**:
* Server IP: `192.168.0.10`
* TCP Port: `30000`



---

## 🕹 Experimental Flow

1. **Initialization**: The operator selects the session mode (*Mix, BI-only, UNI-L, or UNI-R*) via a GUI on the Server.
2. **Barrier Sync**: Both computers enter a 10s black-screen sync phase to align clocks and hardware.
3. **Center Hold**:
* Yellow center appears.
* Subject must move the cursor into the center **AND** trigger the touch sensor.
* Condition must be held for `centerHoldDuration` (default 1.0s).


4. **Target Reach**:
* One of 8 peripheral targets appears.
* Subject must reach and hold the target for `targetHoldDuration`.


5. **Success/Fail**: TTL signals are sent to the neural recording system for "First Move," "Success," and "Trial Start."

---

## Data Outputs

Data is automatically organized into folders (e.g., `/S1_L` and `/S1_R`):

* **Trajectory Files**: `left<N>.xlsx` / `right<N>.xlsx` containing .
* **Summary Data**: A master spreadsheet recording Trial ID, Target Direction, Duration, First Movement Time, and Sync Differences (for bimanual tasks).

---

## Setup Notes

* **Device Mapping**: Ensure NI-DAQ devices are named `Dev3` (Left) and `Dev4` (Right) in NI-MAX.
* **Touch Sensing**: Touch detection is optimized to be active primarily during the hold phases to maximize performance during the movement phase.

---

**Would you like me to add a "Troubleshooting" section specifically for TCP connection errors or NI-DAQ configuration?**
<img width="1280" height="1707" alt="image" src="https://github.com/user-attachments/assets/9bae189c-22a3-4265-90cf-44513f531910" />

