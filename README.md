# Center-Out Touch Tasks

MATLAB-based center-out touch tasks for unimanual and synchronized bimanual experiments. The current bimanual version runs on two networked MATLAB computers: the right-side script acts as the master/server, opens the session setup interface, synchronizes configuration and clocks, schedules trial onsets, and commits final trial outcomes to the left-side client.

## Project Files

| File | Description |
| --- | --- |
| `bimanual_R_mode.m` | Right-side bimanual task. Runs the TCP server, opens the setup UI, synchronizes trial onsets, controls the right NI-DAQ device, and saves right-side data. |
| `bimanual_L_mode.m` | Left-side bimanual task. Connects to the right-side server, receives shared session settings, follows synchronized trial cues, controls the left NI-DAQ device, and saves left-side data. |
| `unimanual_R_touch.m` | Standalone right-side center-out touch task. |
| `unimanual_L_touch.m` | Standalone left-side center-out touch task. |
| `docs/interface-guide.md` | Detailed guide for the setup window, task display, status codes, and output files. |

## Features

- Eight-target center-out layout with a configurable target pool.
- Three bimanual coordination modes:
  - `Inphase`: both hands move to the same direction.
  - `Antiphase`: both hands move to opposite directions.
  - `90deg`: both hands move with 90-degree phase offsets, including clockwise and counter-clockwise pairings.
- Right-side graphical setup interface for shared session configuration.
- TCP-based session configuration, shared clock synchronization, onset scheduling, acknowledgements, and trial commit.
- NI-DAQ digital input/output for touch detection and TTL event markers.
- Per-trial trajectory files and trial-level summary tables in `.xlsx` format.
- Three error handling policies for failed bimanual trials:
  - requeue the failed target pair to the end,
  - immediately redo the failed target pair,
  - reshuffle the remaining target pairs.

## Requirements

- MATLAB with support for nested functions, timers, TCP networking, `jsonencode`, and `jsondecode`.
- Data Acquisition Toolbox.
- NI-DAQmx-compatible devices recognized by MATLAB.
- Two networked computers for bimanual mode.
- MATLAB Java support, used by `java.awt.Robot` to recenter the cursor.

Current device mapping:

| Side | Scripts | NI device | Digital output | Digital input |
| --- | --- | --- | --- | --- |
| Left | `bimanual_L_mode.m`, `unimanual_L_touch.m` | `Dev3` | `port0/line0:4` | `port1/line3` |
| Right | `bimanual_R_mode.m`, `unimanual_R_touch.m` | `Dev4` | `port0/line0:4` | `port1/line3` |

If your NI device names differ, update the `daq("ni")`, `addoutput`, and `addinput` lines in the corresponding script.

## Network Setup For Bimanual Mode

The right-side computer runs as the TCP server:

```matlab
tcpserver("0.0.0.0", 30000, "Timeout", 30)
```

The left-side computer connects to:

```matlab
serverIP = "192.168.0.10";
serverPort = 30000;
```

Before running the bimanual task, make sure the right-side computer uses the expected IP address, or edit `serverIP` in `bimanual_L_mode.m`.

## Quick Start

### Bimanual task

1. Connect both computers to the same network.
2. Confirm that the right-side computer IP matches `serverIP` in `bimanual_L_mode.m`.
3. Open MATLAB on both computers and set the current folder to this project.
4. On the right-side computer, run:

```matlab
bimanual_R_mode
```

5. On the left-side computer, run:

```matlab
bimanual_L_mode
```

6. After both sides connect, configure the session in the setup window on the right-side computer.
7. Click **Confirm & Start**.
8. The right side sends the configuration to the left side, performs shared clock synchronization, and both sides enter the task.

You can also pass a default goal success count:

```matlab
bimanual_R_mode(120)
bimanual_L_mode(120)
```

In bimanual mode, the final shared value is the `Goal successes` value selected in the right-side setup UI.

### Unimanual task

Run the side-specific script on a single computer:

```matlab
unimanual_L_touch
unimanual_R_touch
```

Optional goal success count:

```matlab
unimanual_L_touch(80)
unimanual_R_touch(80)
```

## Task Logic

Each trial starts at the center. The participant touches and holds the center target, then moves to the peripheral target and holds it. In bimanual mode, a successful trial requires both sides to complete the target hold and pass the TTL timing consistency check. If the left/right TTL difference exceeds the configured threshold, the trial is marked as a TTL mismatch.

Default timing and geometry:

| Parameter | Default |
| --- | --- |
| Startup black screen | `10 s` |
| Center hold duration | `0.8 s` |
| Target hold duration | `0.8 s` |
| Target radius from center | `0.24` normalized axis units |
| Center circle diameter | `0.12` |
| Target circle diameter | `0.12` |
| Bimanual first-move threshold | `0.0184` |
| Unimanual first-move threshold | `0.03` |
| Bimanual TTL difference threshold | `0.3 s` |

## Bimanual Setup Interface

The setup interface appears only on the right-side computer.

Main controls:

| Control | Description |
| --- | --- |
| **Target Pool** | Selects which of the eight target directions can appear in the session. |
| **Cardinal 4** | Quickly selects targets `[1, 3, 5, 7]`. |
| **All 8** | Selects all eight targets. |
| **Clear** | Clears the target pool. |
| **Modes** | Enables `Inphase`, `Antiphase`, and/or `90deg` pair generation. |
| **Goal successes** | Sets the number of successful trials required to end the session. |
| **TTL diff threshold (s)** | Sets the maximum allowed left/right TTL timing difference. |
| **Error handling** | Controls how failed pairs are returned to the remaining trial list. |
| **Target circle diameter** | Sets the visual diameter of peripheral targets. |
| **Center circle diameter** | Sets the visual diameter of the center target. |
| **Trial black-screen durations** | Sets candidate inter-trial black-screen durations in seconds. |

The summary box reports the selected targets, selected modes, error policy, valid combinations per balanced block, suggested balanced success counts, and synchronization notes.

## Data Output

Bimanual runs create side-specific output folders in the current MATLAB folder:

```text
S1_R_modes_<mode-tag>_redo_<error-policy>/
S1_L_modes_<mode-tag>_redo_<error-policy>/
```

Example:

```text
S1_R_modes_inphase-antiphase_redo_requeue_to_end/
S1_L_modes_inphase-antiphase_redo_requeue_to_end/
```

Each folder contains:

- `right<N>.xlsx` or `left<N>.xlsx`: cursor/touch trajectory for trial `N`.
- `Summary_Data_R.xlsx` or `Summary_Data_L.xlsx`: trial-level summary table.

Unimanual runs create:

```text
S1R/
S1L/
```

with trajectory files and `Summary_Data.xlsx`.

Generated data folders and spreadsheet files are excluded by `.gitignore` to avoid accidentally uploading experimental output to GitHub.

## Status Codes

| Status | Meaning |
| --- | --- |
| `1` | Success |
| `2` | Left center exit |
| `3` | Left center release |
| `4` | Left target exit |
| `5` | Left target release |
| `6` | Left timeout |
| `7` | Bimanual TTL mismatch |
| `12` | Right center exit |
| `13` | Right center release |
| `14` | Right target exit |
| `15` | Right target release |
| `16` | Right timeout |

## Notes

- The bimanual setup interface is owned by `bimanual_R_mode.m`; the left side waits for configuration and does not show a setup window.
- The task runs in a fullscreen MATLAB figure and hides the system cursor.
- The inter-trial black-screen duration is randomly sampled from the duration list configured in the setup UI.
- See [`docs/interface-guide.md`](docs/interface-guide.md) for a more detailed interface and output-column guide.
