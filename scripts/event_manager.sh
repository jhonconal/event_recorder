#!/bin/sh
# ============================================================================
# event_manager.sh - Linux/Android 输入事件管理脚本 (交互式主入口)
# 整合录制与回放功能，提供交互式菜单
# 用法: sh event_manager.sh
# ============================================================================

SCRIPT_DIR=$(dirname "$0")
RECORDINGS_DIR="${SCRIPT_DIR}/recordings"
RECORDER_SCRIPT="${SCRIPT_DIR}/event_recorder.sh"
PLAYER_SCRIPT="${SCRIPT_DIR}/event_player.sh"

# ---- 颜色定义 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_info()    { echo "${GREEN}[INFO]${NC} $1"; }
print_warn()    { echo "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo "${RED}[ERROR]${NC} $1"; }
print_title()   { echo "${CYAN}$1${NC}"; }

# ---- 显示主菜单 ----
show_menu() {
    echo ""
    print_title "╔══════════════════════════════════════════╗"
    print_title "║     输入事件录制与回放管理工具 v1.0      ║"
    print_title "╠══════════════════════════════════════════╣"
    print_title "║                                          ║"
    print_title "║   1. 录制输入事件                        ║"
    print_title "║   2. 回放输入事件                        ║"
    print_title "║   3. 查看录制文件列表                    ║"
    print_title "║   4. 删除录制文件                        ║"
    print_title "║   5. 退出                                ║"
    print_title "║                                          ║"
    print_title "╚══════════════════════════════════════════╝"
    echo ""
    printf "${BOLD}请选择操作 [1-5]: ${NC}"
}

# ---- 录制输入事件 ----
do_record() {
    echo ""
    print_title "--- 录制输入事件 ---"
    echo ""

    printf "输入录制文件名 (回车使用默认名称): "
    read filename

    if [ -n "$filename" ]; then
        # 确保文件名有 .txt 后缀
        case "$filename" in
            *.txt) ;;
            *) filename="${filename}.txt" ;;
        esac
        sh "$RECORDER_SCRIPT" -o "$filename"
    else
        sh "$RECORDER_SCRIPT"
    fi
}

# ---- 回放输入事件 ----
do_play() {
    echo ""
    print_title "--- 回放输入事件 ---"
    echo ""

    # 确保录制目录存在
    mkdir -p "$RECORDINGS_DIR"

    # 列出可用录制文件
    file_count=0
    file_list=""

    for f in "${RECORDINGS_DIR}"/*.txt; do
        if [ ! -f "$f" ]; then
            continue
        fi
        file_count=$((file_count + 1))
        fname=$(basename "$f")
        fsize=$(ls -l "$f" | awk '{print $5}')
        event_count=$(grep -c "^\[" "$f" 2>/dev/null)
        [ -z "$event_count" ] && event_count=0
        # 使用真实换行符而非字面 \n
        if [ -z "$file_list" ]; then
            file_list="${file_count}:${f}"
        else
            file_list="${file_list}
${file_count}:${f}"
        fi
        echo "  [${file_count}] ${fname}  (${event_count} events, ${fsize} bytes)"
    done

    if [ "$file_count" -eq 0 ]; then
        print_warn "没有找到录制文件！"
        print_info "请先录制输入事件"
        return
    fi

    echo ""
    printf "选择要回放的文件编号 [1-${file_count}]: "
    read choice

    if [ -z "$choice" ] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$file_count" ] 2>/dev/null; then
        print_error "无效选择！"
        return
    fi

    selected_file=$(echo "$file_list" | sed -n "${choice}p" | cut -d':' -f2)

    # 询问回放次数
    printf "回放次数 (默认1, 0=无限循环): "
    read play_count
    if [ -z "$play_count" ]; then
        play_count=1
    fi

    # 询问回放速度
    printf "回放速度倍率 (默认1.0): "
    read play_speed
    if [ -z "$play_speed" ]; then
        play_speed="1.0"
    fi

    echo ""
    sh "$PLAYER_SCRIPT" -i "$selected_file" -n "$play_count" -s "$play_speed"
}

# ---- 查看录制文件列表 ----
do_list() {
    echo ""
    print_title "--- 录制文件列表 ---"
    echo ""

    mkdir -p "$RECORDINGS_DIR"

    file_count=0

    for f in "${RECORDINGS_DIR}"/*.txt; do
        if [ ! -f "$f" ]; then
            continue
        fi
        file_count=$((file_count + 1))
        fname=$(basename "$f")
        fsize=$(ls -l "$f" | awk '{print $5}')
        fdate=$(ls -l "$f" | awk '{print $6, $7, $8}')
        event_count=$(grep -c "^\[" "$f" 2>/dev/null)
        [ -z "$event_count" ] && event_count=0

        device_info=$(grep "^# Device:" "$f" 2>/dev/null | sed 's/^# Device:\s*//')

        echo "  [${file_count}] ${fname}"
        echo "       事件数: ${event_count} | 大小: ${fsize} bytes | 日期: ${fdate}"
        if [ -n "$device_info" ]; then
            echo "       设备: ${device_info}"
        fi
        echo ""
    done

    if [ "$file_count" -eq 0 ]; then
        print_warn "没有找到录制文件"
    else
        print_info "共 ${file_count} 个录制文件"
    fi
}

# ---- 删除录制文件 ----
do_delete() {
    echo ""
    print_title "--- 删除录制文件 ---"
    echo ""

    mkdir -p "$RECORDINGS_DIR"

    file_count=0
    file_list=""

    for f in "${RECORDINGS_DIR}"/*.txt; do
        if [ ! -f "$f" ]; then
            continue
        fi
        file_count=$((file_count + 1))
        fname=$(basename "$f")
        # 使用真实换行符而非字面 \n
        if [ -z "$file_list" ]; then
            file_list="${file_count}:${f}"
        else
            file_list="${file_list}
${file_count}:${f}"
        fi
        echo "  [${file_count}] ${fname}"
    done

    if [ "$file_count" -eq 0 ]; then
        print_warn "没有找到录制文件"
        return
    fi

    echo "  [a] 删除所有文件"
    echo ""
    printf "选择要删除的文件 (编号或 'a'): "
    read choice

    if [ "$choice" = "a" ] || [ "$choice" = "A" ]; then
        printf "${RED}确认删除所有录制文件？(y/n): ${NC}"
        read confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            rm -f "${RECORDINGS_DIR}"/*.txt
            print_info "已删除所有录制文件"
        else
            print_info "已取消"
        fi
    elif [ -n "$choice" ] && [ "$choice" -ge 1 ] && [ "$choice" -le "$file_count" ] 2>/dev/null; then
        selected_file=$(echo "$file_list" | sed -n "${choice}p" | cut -d':' -f2)
        selected_name=$(basename "$selected_file")
        printf "${RED}确认删除 ${selected_name}？(y/n): ${NC}"
        read confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            rm -f "$selected_file"
            print_info "已删除: ${selected_name}"
        else
            print_info "已取消"
        fi
    else
        print_error "无效选择！"
    fi
}

# ---- 主流程 ----
main() {
    # 检查依赖脚本
    if [ ! -f "$RECORDER_SCRIPT" ]; then
        print_error "找不到录制脚本: ${RECORDER_SCRIPT}"
        exit 1
    fi

    if [ ! -f "$PLAYER_SCRIPT" ]; then
        print_error "找不到回放脚本: ${PLAYER_SCRIPT}"
        exit 1
    fi

    # 确保录制目录存在
    mkdir -p "$RECORDINGS_DIR"

    # 主循环
    while true; do
        show_menu
        read action

        case "$action" in
            1) do_record ;;
            2) do_play ;;
            3) do_list ;;
            4) do_delete ;;
            5)
                echo ""
                print_info "再见！"
                exit 0
                ;;
            *)
                print_error "无效选择，请输入 1-5"
                ;;
        esac
    done
}

main "$@"
