#!/bin/sh
# ============================================================================
# event_recorder.sh - Linux/Android 输入事件录制脚本
# 基于 getevent 录制带时间戳的原始输入事件
# 用法: sh event_recorder.sh [-d device] [-o output_file]
# ============================================================================

SCRIPT_DIR=$(dirname "$0")
RECORDINGS_DIR="${SCRIPT_DIR}/recordings"
DEFAULT_OUTPUT="recorded_events_$(date +%Y%m%d_%H%M%S).txt"
DEVICE=""
OUTPUT_FILE=""

# ---- 颜色定义 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info()    { echo "${GREEN}[INFO]${NC} $1"; }
print_warn()    { echo "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo "${RED}[ERROR]${NC} $1"; }
print_title()   { echo "${CYAN}$1${NC}"; }

# ---- 使用帮助 ----
usage() {
    echo ""
    print_title "=========================================="
    print_title "  输入事件录制脚本 (event_recorder.sh)"
    print_title "=========================================="
    echo ""
    echo "用法: sh $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -d <device>     指定输入设备 (如 /dev/input/event2)"
    echo "  -o <output>     指定输出文件名 (默认自动生成带时间戳的文件名)"
    echo "  -h              显示帮助信息"
    echo ""
    echo "示例:"
    echo "  sh $0                      # 自动检测设备，自动命名文件"
    echo "  sh $0 -d /dev/input/event2  # 指定设备"
    echo "  sh $0 -o my_test.txt       # 指定输出文件名"
    echo ""
}

# ---- 扫描输入设备 ----
scan_input_devices() {
    print_info "正在扫描输入设备..."
    echo ""

    INPUT_DEVICES=""
    DEVICE_COUNT=0

    # 遍历所有 input 设备
    for dev in /dev/input/event*; do
        if [ ! -e "$dev" ]; then
            continue
        fi

        # 获取设备名称
        dev_name=$(getevent -p "$dev" 2>/dev/null | grep "name:" | sed 's/.*name:\s*"\(.*\)"/\1/')
        if [ -z "$dev_name" ]; then
            dev_name="Unknown Device"
        fi

        DEVICE_COUNT=$((DEVICE_COUNT + 1))
        # 使用真实换行符而非字面 \n
        if [ -z "$INPUT_DEVICES" ]; then
            INPUT_DEVICES="${DEVICE_COUNT}:${dev}:${dev_name}"
        else
            INPUT_DEVICES="${INPUT_DEVICES}
${DEVICE_COUNT}:${dev}:${dev_name}"
        fi
        echo "  [${DEVICE_COUNT}] ${dev}  -  ${dev_name}"
    done

    if [ "$DEVICE_COUNT" -eq 0 ]; then
        print_error "未发现输入设备！"
        print_warn "请确认:"
        echo "  1. 具有输入设备（鼠标/键盘/触摸屏等）"
        echo "  2. 以 root 权限运行此脚本"
        echo "  3. /dev/input/ 目录下存在 event 设备"
        exit 1
    fi

    echo ""
}

# ---- 选择设备 ----
select_device() {
    if [ "$DEVICE_COUNT" -eq 1 ]; then
        # 只有一个输入设备，自动选择
        DEVICE=$(echo "$INPUT_DEVICES" | head -1 | cut -d':' -f2)
        dev_name=$(echo "$INPUT_DEVICES" | head -1 | cut -d':' -f3)
        print_info "自动选择唯一输入设备: ${DEVICE} (${dev_name})"
    else
        # 多个设备，用户选择
        printf "请选择输入设备编号 [1-${DEVICE_COUNT}]: "
        read choice

        if [ -z "$choice" ] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$DEVICE_COUNT" ] 2>/dev/null; then
            print_error "无效选择！"
            exit 1
        fi

        DEVICE=$(echo "$INPUT_DEVICES" | sed -n "${choice}p" | cut -d':' -f2)
        dev_name=$(echo "$INPUT_DEVICES" | sed -n "${choice}p" | cut -d':' -f3)
        print_info "已选择: ${DEVICE} (${dev_name})"
    fi
}

# ---- 录制事件 ----
record_events() {
    # 确保录制目录存在
    mkdir -p "$RECORDINGS_DIR"

    OUTPUT_PATH="${RECORDINGS_DIR}/${OUTPUT_FILE}"

    echo ""
    print_title "=========================================="
    print_title "         开始录制输入事件"
    print_title "=========================================="
    echo ""
    print_info "设备: ${DEVICE}"
    print_info "输出: ${OUTPUT_PATH}"
    echo ""
    print_warn ">>> 请在屏幕上操作，按 Ctrl+C 停止录制 <<<"
    echo ""

    # 写入录制文件头信息
    echo "# Input Event Recording" > "$OUTPUT_PATH"
    echo "# Date: $(date)" >> "$OUTPUT_PATH"
    echo "# Device: ${DEVICE}" >> "$OUTPUT_PATH"
    echo "# ----------------------------------------" >> "$OUTPUT_PATH"

    # 设置信号处理，优雅退出
    RECORDING_PID=""
    trap 'stop_recording' INT TERM

    # 启动 getevent 录制 (带时间戳)
    getevent -t "$DEVICE" >> "$OUTPUT_PATH" 2>/dev/null &
    RECORDING_PID=$!

    # 等待录制进程结束
    wait $RECORDING_PID 2>/dev/null
}

# ---- 停止录制 ----
stop_recording() {
    echo ""
    print_info "正在停止录制..."

    # 终止 getevent 进程
    if [ -n "$RECORDING_PID" ]; then
        kill $RECORDING_PID 2>/dev/null
        wait $RECORDING_PID 2>/dev/null
    fi

    # 统计录制信息
    if [ -f "$OUTPUT_PATH" ]; then
        EVENT_COUNT=$(grep -c "^\[" "$OUTPUT_PATH" 2>/dev/null)
        [ -z "$EVENT_COUNT" ] && EVENT_COUNT=0
        FILE_SIZE=$(ls -l "$OUTPUT_PATH" | awk '{print $5}')

        echo ""
        print_title "=========================================="
        print_title "           录制完成"
        print_title "=========================================="
        echo ""
        print_info "文件: ${OUTPUT_PATH}"
        print_info "事件数: ${EVENT_COUNT}"
        print_info "文件大小: ${FILE_SIZE} bytes"
        echo ""

        if [ "$EVENT_COUNT" -eq 0 ]; then
            print_warn "未录制到任何事件，请检查设备是否正确！"
        else
            print_info "可使用以下命令回放:"
            echo "  sh ${SCRIPT_DIR}/event_player.sh -i ${OUTPUT_PATH}"
        fi
    else
        print_error "录制文件创建失败！"
    fi

    exit 0
}

# ---- 主流程 ----
main() {
    # 解析参数
    while [ $# -gt 0 ]; do
        case "$1" in
            -d) DEVICE="$2"; shift 2 ;;
            -o) OUTPUT_FILE="$2"; shift 2 ;;
            -h) usage; exit 0 ;;
            *)  print_error "未知参数: $1"; usage; exit 1 ;;
        esac
    done

    # 设置默认输出文件名
    if [ -z "$OUTPUT_FILE" ]; then
        OUTPUT_FILE="$DEFAULT_OUTPUT"
    fi

    print_title ""
    print_title "=========================================="
    print_title "     输入事件录制工具 v1.0"
    print_title "=========================================="

    # 如果未指定设备，自动扫描并选择
    if [ -z "$DEVICE" ]; then
        scan_input_devices
        select_device
    else
        # 验证设备是否存在
        if [ ! -e "$DEVICE" ]; then
            print_error "设备 ${DEVICE} 不存在！"
            exit 1
        fi
        print_info "使用指定设备: ${DEVICE}"
    fi

    # 开始录制
    record_events
}

main "$@"
