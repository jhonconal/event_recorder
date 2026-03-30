#!/bin/sh
# ============================================================================
# event_player.sh - Linux/Android 输入事件回放脚本
# 读取 event_recorder.sh 录制的事件文件，使用 sendevent 精确回放
# 用法: sh event_player.sh -i <input_file> [-n count] [-s speed] [-d device]
# ============================================================================

SCRIPT_DIR=$(dirname "$0")
RECORDINGS_DIR="${SCRIPT_DIR}/recordings"
INPUT_FILE=""
PLAY_COUNT=1
SPEED=1.0
DEVICE_OVERRIDE=""

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
    print_title "  输入事件回放脚本 (event_player.sh)"
    print_title "=========================================="
    echo ""
    echo "用法: sh $0 -i <input_file> [选项]"
    echo ""
    echo "选项:"
    echo "  -i <file>       指定录制文件 (必需)"
    echo "  -n <count>      回放次数 (默认: 1, 0=无限循环)"
    echo "  -s <speed>      回放速度倍率 (默认: 1.0, 2.0=两倍速)"
    echo "  -d <device>     覆盖回放设备路径"
    echo "  -h              显示帮助信息"
    echo ""
    echo "示例:"
    echo "  sh $0 -i recordings/recorded_events.txt"
    echo "  sh $0 -i recordings/recorded_events.txt -n 3      # 回放3次"
    echo "  sh $0 -i recordings/recorded_events.txt -s 2.0    # 两倍速回放"
    echo "  sh $0 -i recordings/recorded_events.txt -n 0      # 无限循环"
    echo ""
}

# ---- Hex 转十进制 (支持负数) ----
hex2dec() {
    hex_val="$1"
    # 去除 0x 前缀
    hex_val=$(echo "$hex_val" | sed 's/^0x//')

    # 使用 printf 转换
    dec_val=$(printf "%d" "0x${hex_val}" 2>/dev/null)
    # 处理 32 位有符号整数负数情况 (例如 ffffffff -> -1)
    if [ "$dec_val" -gt 2147483647 ] 2>/dev/null; then
        dec_val=$((dec_val - 4294967296))
    fi
    echo "$dec_val"
}

# ---- 从录制文件中提取设备路径 ----
get_device_from_file() {
    device_line=$(grep "^# Device:" "$INPUT_FILE" | head -1)
    if [ -n "$device_line" ]; then
        echo "$device_line" | sed 's/^# Device:\s*//' | tr -d ' '
    fi
}

# ---- 验证输入文件 ----
validate_input() {
    if [ ! -f "$INPUT_FILE" ]; then
        print_error "录制文件不存在: ${INPUT_FILE}"
        exit 1
    fi

    EVENT_COUNT=$(grep -c "^\[" "$INPUT_FILE" 2>/dev/null)
    [ -z "$EVENT_COUNT" ] && EVENT_COUNT=0
    if [ "$EVENT_COUNT" -eq 0 ]; then
        print_error "录制文件中没有事件数据！"
        exit 1
    fi

    print_info "事件文件验证通过，共 ${EVENT_COUNT} 个事件"
}

# ---- 回放事件 ----
play_events() {
    # 确定设备路径
    if [ -n "$DEVICE_OVERRIDE" ]; then
        PLAY_DEVICE="$DEVICE_OVERRIDE"
    else
        PLAY_DEVICE=$(get_device_from_file)
    fi

    if [ -z "$PLAY_DEVICE" ]; then
        print_error "无法确定回放设备！请使用 -d 参数指定设备路径"
        exit 1
    fi

    if [ ! -e "$PLAY_DEVICE" ]; then
        print_error "设备 ${PLAY_DEVICE} 不存在！"
        exit 1
    fi

    echo ""
    print_title "=========================================="
    print_title "         开始回放输入事件"
    print_title "=========================================="
    echo ""
    print_info "设备: ${PLAY_DEVICE}"
    print_info "文件: ${INPUT_FILE}"
    print_info "速度: ${SPEED}x"

    if [ "$PLAY_COUNT" -eq 0 ]; then
        print_info "次数: 无限循环"
    else
        print_info "次数: ${PLAY_COUNT}"
    fi

    echo ""
    print_warn ">>> 按 Ctrl+C 停止回放 <<<"
    echo ""

    # 设置信号处理
    PLAYING=1
    trap 'PLAYING=0; echo ""; print_info "回放已停止"; exit 0' INT TERM

    CURRENT_ROUND=0

    while [ "$PLAYING" -eq 1 ]; do
        CURRENT_ROUND=$((CURRENT_ROUND + 1))

        if [ "$PLAY_COUNT" -gt 0 ] && [ "$CURRENT_ROUND" -gt "$PLAY_COUNT" ]; then
            break
        fi

        if [ "$PLAY_COUNT" -eq 0 ]; then
            print_info "=== 回放第 ${CURRENT_ROUND} 轮 (无限模式) ==="
        elif [ "$PLAY_COUNT" -gt 1 ]; then
            print_info "=== 回放第 ${CURRENT_ROUND}/${PLAY_COUNT} 轮 ==="
        fi

        PREV_TIMESTAMP=""
        EVENT_INDEX=0

        # 逐行读取并回放事件
        grep "^\[" "$INPUT_FILE" | while IFS= read -r line; do
            if [ "$PLAYING" -ne 1 ]; then
                break
            fi

            # 解析行: [ timestamp] device_path: type code value
            # 格式示例: [     123.456789] /dev/input/event2: 0003 0039 00000001
            TIMESTAMP=$(echo "$line" | sed 's/\[\s*//' | sed 's/\].*//' | tr -d ' ')
            # 使用 NF 倒数获取字段，兼容带不带返回设备路径的 getevent 格式
            TYPE_HEX=$(echo "$line" | awk '{print $(NF-2)}')
            CODE_HEX=$(echo "$line" | awk '{print $(NF-1)}')
            VALUE_HEX=$(echo "$line" | awk '{print $NF}')

            # 跳过解析失败的行
            if [ -z "$TYPE_HEX" ] || [ -z "$CODE_HEX" ] || [ -z "$VALUE_HEX" ]; then
                continue
            fi

            # 计算延时
            if [ -n "$PREV_TIMESTAMP" ]; then
                DELAY=$(awk "BEGIN {
                    d = ${TIMESTAMP} - ${PREV_TIMESTAMP};
                    if (d < 0) d = 0;
                    d = d / ${SPEED};
                    printf \"%.6f\", d
                }")

                # 仅在延时大于 0.0005 秒时 sleep
                SHOULD_SLEEP=$(awk "BEGIN { print (${DELAY} > 0.0005) ? 1 : 0 }")
                if [ "$SHOULD_SLEEP" -eq 1 ]; then
                    sleep "$DELAY"
                fi
            fi
            PREV_TIMESTAMP="$TIMESTAMP"

            # Hex 转十进制
            TYPE_DEC=$(hex2dec "$TYPE_HEX")
            CODE_DEC=$(hex2dec "$CODE_HEX")
            VALUE_DEC=$(hex2dec "$VALUE_HEX")

            # 发送事件
            sendevent "$PLAY_DEVICE" "$TYPE_DEC" "$CODE_DEC" "$VALUE_DEC"

            EVENT_INDEX=$((EVENT_INDEX + 1))
        done

        # 轮次间隔
        if [ "$PLAY_COUNT" -eq 0 ] || [ "$CURRENT_ROUND" -lt "$PLAY_COUNT" ]; then
            print_info "轮次间隔 1 秒..."
            sleep 1
        fi
    done

    echo ""
    print_title "=========================================="
    print_title "           回放完成"
    print_title "=========================================="
    echo ""
}

# ---- 主流程 ----
main() {
    # 解析参数
    while [ $# -gt 0 ]; do
        case "$1" in
            -i) INPUT_FILE="$2"; shift 2 ;;
            -n) PLAY_COUNT="$2"; shift 2 ;;
            -s) SPEED="$2"; shift 2 ;;
            -d) DEVICE_OVERRIDE="$2"; shift 2 ;;
            -h) usage; exit 0 ;;
            *)  print_error "未知参数: $1"; usage; exit 1 ;;
        esac
    done

    if [ -z "$INPUT_FILE" ]; then
        print_error "请指定录制文件！"
        usage
        exit 1
    fi

    print_title ""
    print_title "=========================================="
    print_title "     输入事件回放工具 v1.0"
    print_title "=========================================="

    # 验证输入文件
    validate_input

    # 开始回放
    play_events
}

main "$@"
