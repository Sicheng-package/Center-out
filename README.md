# Center-Out Touch Tasks

这是一个基于 MATLAB 的 center-out 触控任务项目，包含单手任务和双手同步任务。当前双手版本使用两台 MATLAB 电脑通过 TCP/IP 通信：右手端作为 master/server，负责打开参数配置界面、同步配置和时钟、发起试次开始信号，并把最终试次结果提交给左手端。

## 文件结构

| 文件 | 作用 |
| --- | --- |
| `bimanual_R_mode.m` | 双手任务右手端。作为 TCP server，打开配置界面，同步试次 onset，控制右侧 NI-DAQ，并保存右手数据。 |
| `bimanual_L_mode.m` | 双手任务左手端。连接右手端 server，接收共享配置，按同步信号执行试次，控制左侧 NI-DAQ，并保存左手数据。 |
| `unimanual_R_touch.m` | 右手单手 center-out 触控任务。 |
| `unimanual_L_touch.m` | 左手单手 center-out 触控任务。 |
| `docs/interface-guide.md` | 配置窗口、任务界面、状态码和输出文件的详细说明。 |

## 功能特点

- 八方向 center-out 目标布局，可在界面中选择目标池。
- 支持三类双手运动模式：
  - `Inphase`：左右手同方向运动。
  - `Antiphase`：左右手反方向运动。
  - `90deg`：左右手相差 90 度运动，包含顺时针和逆时针两个方向。
- 右手端提供图形化配置界面，左手端自动接收同一套 session 参数。
- 双手任务包含 TCP 配置同步、共享时钟同步、onset 调度、acknowledgement 和 trial commit。
- 使用 NI-DAQ 数字输入/输出进行触控检测和 TTL 事件标记。
- 每个 trial 保存轨迹数据和 trial-level summary 表格。
- 支持三种错误处理策略：
  - 失败组合排到剩余队列末尾；
  - 失败组合立即重做；
  - 失败组合放回后重新打乱剩余队列。

## 环境要求

- MATLAB，需支持 nested functions、timer、TCP networking、`jsonencode` 和 `jsondecode`。
- Data Acquisition Toolbox。
- MATLAB 可识别的 NI-DAQmx 设备。
- 双手任务需要两台处于同一网络下的电脑。
- MATLAB Java 支持；脚本使用 `java.awt.Robot` 将鼠标重新居中。

当前脚本中的设备映射如下：

| 侧别 | 脚本 | NI device | Digital output | Digital input |
| --- | --- | --- | --- | --- |
| 左手 | `bimanual_L_mode.m`, `unimanual_L_touch.m` | `Dev3` | `port0/line0:4` | `port1/line3` |
| 右手 | `bimanual_R_mode.m`, `unimanual_R_touch.m` | `Dev4` | `port0/line0:4` | `port1/line3` |

如果实际设备名不同，请在对应脚本里修改 `daq("ni")`、`addoutput` 和 `addinput` 相关行。

## 双手任务网络设置

右手端作为 server：

```matlab
tcpserver("0.0.0.0", 30000, "Timeout", 30)
```

左手端连接右手端：

```matlab
serverIP = "192.168.0.10";
serverPort = 30000;
```

运行双手任务前，请确认右手电脑的 IP 地址与 `bimanual_L_mode.m` 中的 `serverIP` 一致；如果不一致，先修改 `serverIP`。

## 快速开始

### 双手任务

1. 将两台电脑连接到同一网络。
2. 确认右手电脑 IP 与 `bimanual_L_mode.m` 中的 `serverIP` 一致。
3. 两台电脑都打开 MATLAB，并将 current folder 设置为本项目目录。
4. 在右手电脑运行：

```matlab
bimanual_R_mode
```

5. 在左手电脑运行：

```matlab
bimanual_L_mode
```

6. 两端连接后，右手电脑会弹出配置窗口。
7. 配置目标、模式、成功数和时间参数后，点击 **Confirm & Start**。
8. 右手端会把配置发送给左手端，完成共享时钟同步，然后两边进入任务界面。

也可以传入默认成功数：

```matlab
bimanual_R_mode(120)
bimanual_L_mode(120)
```

双手任务最终使用右手端配置界面中的 `Goal successes` 作为共享 session 设置。

### 单手任务

在对应电脑上运行单手脚本：

```matlab
unimanual_L_touch
unimanual_R_touch
```

也可以传入目标成功数：

```matlab
unimanual_L_touch(80)
unimanual_R_touch(80)
```

## 任务逻辑

每个 trial 从中心点开始。被试需要触碰并保持中心点，随后移动到目标点并保持。双手任务中，左右两侧都完成目标保持后，脚本会检查左右 TTL 时间差；若超过阈值，则该 trial 标记为 TTL mismatch。

默认时间和几何参数：

| 参数 | 默认值 |
| --- | --- |
| 启动黑屏 | `10 s` |
| 中心保持时间 | `0.8 s` |
| 目标保持时间 | `0.8 s` |
| 目标到中心距离 | `0.24` normalized axis units |
| 中心圆直径 | `0.12` |
| 目标圆直径 | `0.12` |
| 双手 first-move 阈值 | `0.0184` |
| 单手 first-move 阈值 | `0.03` |
| 双手 TTL 时间差阈值 | `0.3 s` |

## 数据输出

双手任务会在当前 MATLAB 目录下生成左右两侧的数据文件夹：

```text
S1_R_modes_<mode-tag>_redo_<error-policy>/
S1_L_modes_<mode-tag>_redo_<error-policy>/
```

示例：

```text
S1_R_modes_inphase-antiphase_redo_requeue_to_end/
S1_L_modes_inphase-antiphase_redo_requeue_to_end/
```

每个文件夹包含：

- `right<N>.xlsx` 或 `left<N>.xlsx`：第 `N` 个 trial 的鼠标/触控轨迹。
- `Summary_Data_R.xlsx` 或 `Summary_Data_L.xlsx`：trial-level 汇总表。

单手任务会生成：

```text
S1R/
S1L/
```

其中包含 trial 轨迹文件和 `Summary_Data.xlsx`。

`.gitignore` 已排除运行时生成的数据文件夹和表格文件，避免把实验数据误传到 GitHub。

## 状态码

| Status | 含义 |
| --- | --- |
| `1` | 成功 |
| `2` | 左手中心点移出 |
| `3` | 左手中心点释放 |
| `4` | 左手目标点移出 |
| `5` | 左手目标点释放 |
| `6` | 左手超时 |
| `7` | 双手 TTL 时间差超阈值 |
| `12` | 右手中心点移出 |
| `13` | 右手中心点释放 |
| `14` | 右手目标点移出 |
| `15` | 右手目标点释放 |
| `16` | 右手超时 |

## 备注

- 双手任务的配置界面只出现在 `bimanual_R_mode.m` 右手端；左手端只等待配置并执行同步任务。
- 任务运行时使用 fullscreen MATLAB figure，并隐藏系统光标。
- trial 之间的黑屏时间会从配置界面中填写的候选时间里随机抽取。
- 更详细的界面和输出列说明见 [`docs/interface-guide.md`](docs/interface-guide.md)。
