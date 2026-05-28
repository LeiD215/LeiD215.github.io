#!/bin/bash

# 打印帮助信息
show_help() {
    echo "使用方法:"
    echo "  新建Swap:   $0 {大小} [路径] [--auto|-y]"
    echo "  卸载Swap:   $0 --uninstall [路径]"
    echo "例如:"
    echo "  $0 4G                 (交互式创建 4G Swap)"
    echo "  $0 2G /myswap --auto  (无人值守自动创建 2G Swap 到指定路径)"
    echo "  $0 --uninstall        (卸载默认的 /swapfile)"
    exit 1
}

# 检查基础参数
if [ "$#" -lt 1 ]; then show_help; fi

SWAP_PATH="/swapfile"
AUTO_MODE=false
UNINSTALL_MODE=false

# 解析参数 (纯 sh 兼容语法)
for arg in "$@"; do
    case $arg in
        --uninstall) UNINSTALL_MODE=true ;;
        --auto|-y) AUTO_MODE=true ;;
        *) 
            case $arg in
                *[0-9][MGmg]) SWAP_SIZE=$arg ;; 
                /*)           SWAP_PATH=$arg ;; 
            esac
            ;;
    esac
done

## ==================== 卸载模式 ====================
if [ "$UNINSTALL_MODE" = "true" ]; then
    echo "=== 开始卸载 Swap 空间 ==="
    if [ -f "$SWAP_PATH" ]; then
        sudo swapoff $SWAP_PATH 2>/dev/null
        sudo rm -f $SWAP_PATH
        sudo sed -i "\| $SWAP_PATH |d" /etc/fstab
        echo "✅ 已关闭并删除 Swap 文件: $SWAP_PATH"
    else
        echo "ℹ️ 未找到 Swap 文件: $SWAP_PATH，无需处理。"
    fi
    
    SYSCTL_CONF="/etc/sysctl.d/99-swap-optimize.conf"
    if [ -f "$SYSCTL_CONF" ]; then
        sudo rm -f $SYSCTL_CONF
        sudo sysctl --system
        echo "✅ 已删除内核优化配置文件，并重置内核状态。"
    fi
    echo "🎉 卸载完成！"
    exit 0
fi

## ==================== 创建模式 ====================
if [ -z "$SWAP_SIZE" ]; then
    echo "❌ 错误: 未指定 Swap 大小 (如 2G, 4G)"
    show_help
fi

if [ -f "$SWAP_PATH" ]; then
    echo "⚠️ 错误: 路径 $SWAP_PATH 已经存在，脚本退出以防覆盖数据。"
    exit 1
fi

# 1. 智能检测历史配置冲突
echo "🔍 正在检测系统原有的内核参数设置..."
CURRENT_SWAP=$(sysctl -n vm.swappiness 2>/dev/null)
CURRENT_PRES=$(sysctl -n vm.vfs_cache_pressure 2>/dev/null)

CONF_FILES=$(grep -lR -E '^vm.(swappiness|vfs_cache_pressure)' /etc/sysctl.conf /etc/sysctl.d/ 2>/dev/null)

if [ ! -z "$CONF_FILES" ]; then
    echo "⚠️ 检测到系统原配置文件中已存在相关设置："
    echo "   ----------------------------------------"
    echo "   当前内核实际生效值: swappiness=$CURRENT_SWAP, vfs_cache_pressure=$CURRENT_PRES"
    echo "   冲突的配置文件路径:"
    for file in $CONF_FILES; do
        echo "   📄 $file"
    done
    echo "   ----------------------------------------"
    
    if [ "$AUTO_MODE" = "true" ]; then
        echo "🚀 已启用无人值守模式，将自动清理旧冲突并覆盖。"
        OVERWRITE_CHOICE="y"
    else
        read -p "是否清理旧的冲突配置并强行覆盖？[y/n, 默认 y]: " OVERWRITE_CHOICE
        : ${OVERWRITE_CHOICE:="y"}
    fi
    
    if [ "$OVERWRITE_CHOICE" = "y" ] || [ "$OVERWRITE_CHOICE" = "Y" ]; then
        echo "🧹 正在清理旧配置文件中的冲突行..."
        for file in $CONF_FILES; do
            sudo cp "$file" "${file}.bak"
            sudo sed -i '/^vm.swappiness/d' "$file"
            sudo sed -i '/^vm.vfs_cache_pressure/d' "$file"
        done
        echo "✅ 旧冲突清理完毕（已为您自动生成 .bak 备份文件）。"
    else
        echo "❌ 用户取消操作，脚本停止。"
        exit 0
    fi
else
    echo "ℹ️ 系统环境纯净，未发现任何内核参数冲突。"
fi
echo

# 2. 从底层 /proc/meminfo 读取总内存 (转换成 MB)
TOTAL_RAM_KB=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
TOTAL_RAM=$((TOTAL_RAM_KB / 1024))
echo "ℹ️ 总物理内存: ${TOTAL_RAM} MB"

if [ "$TOTAL_RAM" -le 1024 ]; then sw=60; pr=100; stage="1G内存 复合Web";
elif [ "$TOTAL_RAM" -le 2048 ]; then sw=30; pr=80;  stage="2G内存
