# event_tool (Linux Qt5 Input Event Recorder & Player)

`event_tool` 是基于 Linux Qt5 Core 开发的控制台（CLI）输入事件录制与回放工具。  
它的主要目的是为了替代原有的 `getevent/sendevent` Shell 脚本，提供更高效、更精准（无解析延迟）以及同时支持 **明文/二进制加密格式** 的输入事件回放与录制方案。

## 1. 特性

- **精准时间回放**：内部使用高精度定时器比对时间戳差值，在内核进行输入注入，确保还原度。
- **混合存储格式**：通过修改宏 `USE_PLAINTEXT_FORMAT` 支持生成方便人类阅读的文本日志结构（类似 `getevent`），也可以支持高速序列化的紧凑二进制（加密）结构。
- **免依赖 GUI 模块**：仅依赖 `Qt5Core` 模块，可以直接在无屏幕（Headless）目标 Linux 主机或开发板上执行。
- **内置设备侦测**：自动获取并打印 `/dev/input/` 下所有存在的可用设备及其设备名称。

## 2. 编译指南

该工程为标准 QMake 工程，无需 Qt GUI 关联。由于涉猎到完整的 `<linux/input.h>` 内核头文件调用，**必须在 Linux (Ubuntu/Debian 或任何交叉编译链系统)** 下执行编译。

```bash
# 进入工程目录
cd event_recorder/event_tool

# 使用 qmake 生成 Makefile (请确保你已经安装了 Qt5 开发环境)
# 在 Ubuntu 上例如：sudo apt install qtbase5-dev qt5-qmake
qmake

# 编译生成可执行文件 `event_tool`
make
```

## 3. 使用方法

工具使用子命令的模式，支持 `list`, `record`, `play`。  
**注意：** 对 `/dev/input/eventX` 节点的读写通常需要 `root` 权限或者处于 `input` 用户组。请使用 `sudo` 执行以下命令，否则可能会遇到 Permission Denied 错误。

### 3.1 罗列全部输入设备 `list`
列出当前系统下所有的输入设备（包括键盘、触摸屏、鼠标等）：
```bash
sudo ./event_tool list
```

### 3.2 录制输入事件 `record`
使用 `-d` 挂载对应设备录制输入。默认存放到 `recordings/` 目录并使用时间戳命名：
```bash
sudo ./event_tool record -d /dev/input/event2

# 或者指定存放的文件路径
sudo ./event_tool record -d /dev/input/event2 -o my_touch_events.txt
```
> **提示**：在使用期间任意时刻键入 `Ctrl + C`，即可安全地结束捕捉并保存文件。

### 3.3 回放输入事件 `play`
重放刚刚捕获到的轨迹。它会自动分析并适配捕获时间内的按键毫秒级按压和延迟。
```bash
sudo ./event_tool play -i my_touch_events.txt
```

**可选参数 (play)：**
- `-d <device>`: 强制覆盖写入特定设备节点，例如将 event2 生成的文件强制丢入到 event3 `/dev/input/event3`。
- `-s <speed>`: 指定快进倍率（如：`-s 2.0` 代表 2 倍音速加速重放）。
- `-n <loop>`:  配置循环次数。默认为 `1`（一遍）。当设置为 `0` 时，启动无限循环播放方案。

```bash
# 例子: 将录制的文件重放给 event3，进行 2 倍加速，且永远重复
sudo ./event_tool play -i my_touch_events.txt -d /dev/input/event3 -s 2.0 -n 0
```

## 4. 格式调整 (明文 vs 二进制)
如果你想把生成的格式从可读明文（Plaintext）转为完全序列化的紧密字节（Binary 加密模式），请编辑 `event_manager.cpp` 文件顶部的宏：

```cpp
// 0 代表纯二进制，1 代表明文文本格式
#define USE_PLAINTEXT_FORMAT 1
```
更改后请执行：
```bash
make clean && make
```
