# 界面说明

本文档说明当前双手任务的配置窗口、任务显示界面、状态码和输出文件格式。

## 启动流程

1. 在右手电脑运行 `bimanual_R_mode.m`。
2. 在左手电脑运行 `bimanual_L_mode.m`。
3. 右手端在 `30000` 端口等待 TCP 连接。
4. 左手端连接 `bimanual_L_mode.m` 中写定的右手端 IP。
5. 连接成功后，右手电脑弹出 **Bimanual Modes Setup** 配置窗口。
6. 确认配置后，右手端将 session 参数发送给左手端，并进行共享时钟同步。
7. 左右两侧同时进入 `10 s` 启动黑屏，然后开始同步任务。

## Bimanual Modes Setup 配置窗口

配置窗口只在右手电脑显示。左手电脑连接成功后等待右手端发送参数。

### Target Pool

`Target Pool` 区域用于选择本 session 中可出现的目标方向。界面上的八个方向如下：

| Target | 方向 |
| --- | --- |
| `1` | East，右 |
| `2` | North-East，右上 |
| `3` | North，上 |
| `4` | North-West，左上 |
| `5` | West，左 |
| `6` | South-West，左下 |
| `7` | South，下 |
| `8` | South-East，右下 |

控件说明：

| 控件 | 作用 |
| --- | --- |
| 目标按钮 | 点击后包含或排除该方向。被选中的目标会变成深绿色。 |
| **Cardinal 4** | 快速选择 `[1, 3, 5, 7]` 四个正方向目标。 |
| **All 8** | 选择全部八个目标。 |
| **Clear** | 清空当前目标池。 |
| **Selected targets** | 显示当前已选择的目标数量和目标编号。 |

### Session Settings

`Session Settings` 区域用于设置双手任务模式、成功数、TTL 阈值和视觉参数。

| 控件 | 含义 |
| --- | --- |
| **Inphase (same direction)** | 添加左右手同方向目标组合。 |
| **Antiphase (opposite direction)** | 添加左右手相差 180 度的目标组合；只有组合中的两个目标都在目标池中时才保留。 |
| **90deg phase (cw and ccw)** | 添加左右手相差正负 90 度的目标组合；顺时针和逆时针两种组合都会生成。 |
| **Goal successes** | 达到多少个成功 trial 后结束 session。 |
| **TTL diff threshold (s)** | 左右 TTL 时间差允许范围；超过该值时 trial 标记为 TTL mismatch。 |
| **Error handling** | 失败 trial 的目标组合如何回到剩余队列。 |
| **Target circle diameter** | 外周目标圆直径，单位为 MATLAB 归一化坐标。 |
| **Center circle diameter** | 中心圆直径，单位为 MATLAB 归一化坐标。 |
| **Trial black-screen durations** | trial 间黑屏候选时长，单位秒，可用逗号、空格或分号分隔。 |

### Summary Box

配置窗口下方的 summary box 会实时更新当前 session 设计：

| 区域 | 显示内容 |
| --- | --- |
| **Selection** | 当前目标池、模式选择和错误处理策略。 |
| **Balance** | 一个完整平衡 block 中包含多少个有效 trial 组合。 |
| **Timing & Size** | TTL 阈值、目标圆直径、中心圆直径和黑屏候选时间。 |
| **Sync** | 提示右手端会在启动黑屏前把配置同步给左手端。 |

如果 `Goal successes` 不是完整平衡 block 大小的整数倍，界面会提示当前设计最后会出现不完全平衡，并给出相邻的平衡成功数建议。

### 底部按钮

| 按钮 | 作用 |
| --- | --- |
| **Confirm & Start** | 验证参数，关闭配置窗口，同步配置到左手端，并启动任务。 |
| **Reset Defaults** | 恢复默认目标、模式、成功数、TTL 阈值、圆大小和错误策略。 |
| **Cancel** | 取消 session，并向左手端发送 stop 信号。 |

## 双手模式定义

目标组合由所选目标池和所选模式共同生成。

| ModeId | 模式 | 组合规则 |
| --- | --- | --- |
| `1` | Inphase | `LeftTarget = RightTarget` |
| `2` | Antiphase | `RightTarget = LeftTarget + 180 degrees` |
| `3` | 90deg | `RightTarget = LeftTarget + 90 degrees` 和 `RightTarget = LeftTarget - 90 degrees` |

只有左右目标都存在于当前目标池中的组合会被保留。每个 block 开始时，组合列表会随机打乱。

## 错误处理策略

| 界面选项 | 文件名标签 | 行为 |
| --- | --- | --- |
| Requeue To End | `requeue_to_end` | 失败组合追加到剩余队列末尾。 |
| Immediate Redo | `immediate_redo` | 失败组合插入到剩余队列开头，下一次立即重做。 |
| Reshuffle Remaining | `reshuffle_remaining` | 失败组合放回剩余队列，然后重新随机打乱。 |

成功完成的组合会从当前 block 中移除。

## 任务显示界面

任务界面是 fullscreen 黑色 MATLAB figure：

| 状态 | 显示内容 |
| --- | --- |
| 启动黑屏或 trial 间黑屏 | 全屏黑色 panel 覆盖任务界面。 |
| 中心保持阶段 | 只显示白色中心圆。 |
| 目标保持阶段 | 只显示当前外周目标圆。 |
| 等待同步 onset | 所有任务目标隐藏。 |

其他显示特征：

- 系统鼠标光标被隐藏。
- 红色大点表示当前控制位置。
- 外周目标是白色虚线圆。
- 中心目标是白色实心圆。
- 黑屏期间鼠标回调被暂时关闭，避免黑屏中记录额外动作。

## 双手 summary 输出列

右手端输出 `Summary_Data_R.xlsx`，左手端输出 `Summary_Data_L.xlsx`。

| 列名 | 含义 |
| --- | --- |
| `Trial` | Trial 编号。 |
| `LocalTarget` | 本侧显示的目标编号。 |
| `PartnerTarget` | 对侧分配到的目标编号。 |
| `ModeId` | `1` 为 inphase，`2` 为 antiphase，`3` 为 90-degree phase。 |
| `Dur` | Trial 总时长。 |
| `FirstMoveTime` | 相对中心 onset 的首次移动时间。 |
| `TargetOnTime` | 相对中心 onset 的目标出现时间。 |
| `Status` | Trial 最终状态码。 |
| `TTL_FirstMove` | 相对中心 onset 的 first-move TTL 时间。 |
| `TTL_End` | 相对中心 onset 的结束 TTL 时间。 |
| `TTL_StartDiff` | 左右 first-move TTL 时间差。 |
| `TTL_EndDiff` | 左右结束 TTL 时间差。 |
| `Centerexittime` | 中心保持结束或中心退出记录时间。 |
| `TouchCenterStart` | 中心保持阶段触控开始时间。 |
| `TouchTargetStart` | 目标保持阶段触控开始时间。 |
| `MoveEnd` | 目标保持完成时间。 |
| `BlackScreenDur` | 本 trial 之后使用的黑屏时长。 |
| `CenterOnTime` | 相对 trial 的中心出现时间。 |
| `CenterOnSharedTime` | 共享时钟中的中心出现时间。 |
| `FirstMoveSharedTime` | 共享时钟中的首次移动时间。 |
| `TargetOnSharedTime` | 共享时钟中的目标出现时间。 |
| `TTL_FirstMoveShared` | 共享时钟中的 first-move TTL 时间。 |
| `TTL_EndShared` | 共享时钟中的结束 TTL 时间。 |
| `CenterExitSource` | 中心退出时间来源代码。 |
| `CenterExitWriteSharedTime` | 写入中心退出时间时的共享时钟时间。 |
| `FallbackTriggered` | 是否触发 fallback finalization；`1` 表示触发。 |
| `FallbackReason` | fallback finalization 的文字原因。 |

## 单手 summary 输出列

单手脚本会在 `S1L/` 或 `S1R/` 中写入 `Summary_Data.xlsx`。

| 列名 | 含义 |
| --- | --- |
| `Trial` | Trial 编号。 |
| `Target` | 目标编号。 |
| `Dur` | Trial 总时长。 |
| `FirstMoveTime` | 首次移动时间。 |
| `TargetOnTime` | 目标出现时间。 |
| `Status` | Trial 状态码。 |
| `TTL_FirstMove` | First-move TTL 时间。 |
| `TTL_End` | 结束 TTL 时间。 |
| `CenterExitTime` | 中心退出时间。 |
| `CenterHoldStartTime` | 中心保持开始时间。 |
| `TargetHoldStartTime` | 目标保持开始时间。 |
| `MoveEnd` | 移动结束或目标保持完成时间。 |
| `BlackScreenDur` | Trial 间黑屏时长。 |

## GitHub 上传建议

建议上传：

- `README.md`
- `docs/interface-guide.md`
- `bimanual_R_mode.m`
- `bimanual_L_mode.m`
- `unimanual_R_touch.m`
- `unimanual_L_touch.m`
- `.gitignore`

不建议上传运行生成的数据文件夹，例如 `S1L/`、`S1R/`、`S1_L_*`、`S1_R_*`，除非你明确希望公开实验数据。
