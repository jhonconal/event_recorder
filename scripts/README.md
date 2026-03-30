# 触摸事件录制与回放工具

基于 Linux `getevent`/`sendevent` 实现触摸屏事件的录制和自动回放，适用于 Android/Linux 嵌入式设备自动化测试。

## 功能特性

- **自动检测** 触摸输入设备
- **精确录制** 带时间戳的原始触摸事件
- **精确回放** 按原始时间间隔重放触摸动作
- **速度控制** 支持加速/减速回放
- **循环回放** 支持指定次数或无限循环
- **交互管理** 菜单式操作界面

## 文件说明

```
event_recorder_scripts/
├── event_recorder.sh    # 录制脚本
├── event_player.sh      # 回放脚本
├── event_manager.sh     # 交互式管理入口
├── recordings/          # 录制数据存储目录 (自动创建)
└── README.md            # 本文件
```

## 快速开始

### 1. 推送到设备

```bash
adb push event_recorder_scripts/ /data/local/tmp/
adb shell chmod +x /data/local/tmp/event_recorder_scripts/*.sh
adb shell
cd /data/local/tmp/event_recorder_scripts
```

### 2. 使用交互式管理工具 (推荐)

```bash
sh event_manager.sh
```

按照菜单提示操作即可完成录制和回放。

### 3. 单独使用录制脚本

```bash
# 自动检测设备，开始录制
sh event_recorder.sh

# 指定设备录制
sh event_recorder.sh -d /dev/input/event2

# 指定输出文件名
sh event_recorder.sh -o my_test.txt
```

录制过程中在屏幕上操作，按 `Ctrl+C` 停止录制。

### 4. 单独使用回放脚本

```bash
# 基本回放
sh event_player.sh -i recordings/recorded_events.txt

# 回放 3 次
sh event_player.sh -i recordings/recorded_events.txt -n 3

# 两倍速回放
sh event_player.sh -i recordings/recorded_events.txt -s 2.0

# 无限循环回放
sh event_player.sh -i recordings/recorded_events.txt -n 0

# 指定回放设备
sh event_player.sh -i recordings/recorded_events.txt -d /dev/input/event3
```

## 命令参数

### event_recorder.sh

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `-d <device>` | 输入设备路径 | 自动检测 |
| `-o <file>` | 输出文件名 | 自动生成带时间戳文件名 |
| `-h` | 显示帮助 | - |

### event_player.sh

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `-i <file>` | 录制文件路径 (必需) | - |
| `-n <count>` | 回放次数 (0=无限) | 1 |
| `-s <speed>` | 速度倍率 | 1.0 |
| `-d <device>` | 覆盖回放设备 | 从录制文件读取 |
| `-h` | 显示帮助 | - |

## 运行环境

- **系统**: Android / 嵌入式 Linux
- **权限**: 需要 root 权限
- **依赖**: `getevent`, `sendevent`, `awk`, `sleep`
- **Shell**: `sh` (POSIX 兼容)

## 工作原理

### 录制

1. 扫描 `/dev/input/` 下具有 `ABS_MT_POSITION_X` (0x0035) 能力的触摸设备
2. 使用 `getevent -t` 捕获带时间戳的原始事件数据
3. 事件数据以 hex 格式保存到文件

### 回放

1. 解析录制文件中的时间戳和事件类型/代码/值
2. 计算相邻事件的时间差，使用 `sleep` 实现精确延时
3. 将 hex 值转换为十进制，通过 `sendevent` 注入事件

### 录制文件格式

```
# Touch Event Recording
# Date: Thu Mar 26 23:22:00 CST 2026
# Device: /dev/input/event2
# ----------------------------------------
[     123.456789] 0003 0039 00000001
[     123.456800] 0003 0035 000001a0
[     123.456800] 0003 0036 00000320
[     123.456810] 0000 0000 00000000
```

## 注意事项

1. 必须以 **root** 权限运行
2. 回放时请勿同时手动触摸屏幕，以免事件冲突
3. 不同设备的触摸设备路径可能不同，跨设备回放时需使用 `-d` 参数指定设备
4. 录制文件越大回放越耗时，建议单次录制时长不超过 5 分钟
