#!/bin/sh

# =================================================================
#  虚拟内存自适应管理与调优脚本 (POSIX sh 100% 兼容完全体版)
# =================================================================

SYSCTL_CONF="/etc/sysctl.d/99-dleia-swapopt.conf"
SWAP_PATH="/swapfile"
AUTO_MODE=false
UNINSTALL_MODE=false
SWAP_SIZE=""

show_help() {
    printf "使用方法:\n"
    printf "  新建Swap:   $0 {大小} [路径] [--auto|-y]\n"
    printf "  卸载Swap:   $0 --uninstall [路径]\n"
    printf "例如:\n"
    printf "  $0 4G                 (交互式创建 4G Swap)\n"
    printf "  $0 2G /myswap --auto  (无人值守自动创建 2G Swap 到指定路径)\n"
    printf "  $0 --uninstall        (卸载默认的 /swapfile)\n"
    exit 1
}

if [ "$#" -lt 1 ]; then show_help; fi

# 解析参数 (纯 sh 通用兼容状态机)
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
    printf "=== 开始卸载 Swap 空间 ===\n"
    if [ -f "$SWAP_PATH" ]; then
        sudo swapoff "$SWAP_PATH" 2>/dev/null
        sudo rm -f "$SWAP_PATH"
        sudo sed -i "\| $SWAP_PATH |d" /etc/fstab
        printf "✅ 已关闭并删除 Swap 文件: %s\n" "$SWAP_PATH"
    else
        printf "ℹ️ 未找到 Swap 文件: %s，无需处理。\n" "$SWAP_PATH"
    fi
    
    if [ -f "$SYSCTL_CONF" ]; then
        sudo rm -f "$SYSCTL_CONF"
        sudo sysctl --system >/dev/null 2>&1
        printf "✅ 已删除内核优化配置文件，并重置内核状态。\n"
    fi
    printf "🎉 卸载完成！\n"
    exit 0
fi

## ==================== 创建模式 ====================
if [ -z "$SWAP_SIZE" ]; then
    printf "❌ 错误: 未指定 Swap 大小 (如 2G, 4G)\n"
    show_help
fi

if [ -f "$SWAP_PATH" ]; then
    printf "⚠️ 错误: 路径 %s 已经存在，脚本退出以防覆盖数据。\n" "$SWAP_PATH"
    exit 1
fi

printf "🔍 正在检测系统原有的内核参数设置...\n"
CURRENT_SWAP=$(sysctl -n vm.swappiness 2>/dev/null)
CURRENT_PRES=$(sysctl -n vm.vfs_cache_pressure 2>/dev/null)

CONF_FILES=$(grep -lR -E '^vm.(swappiness|vfs_cache_pressure)' /etc/sysctl.conf /etc/sysctl.d/ 2>/dev/null)

if [ -n "$CONF_FILES" ]; then
    printf "⚠️ 检测到系统原配置文件中已存在相关设置：\n"
    printf "   ----------------------------------------\n"
    printf "   当前内核实际生效值: swappiness=%s, vfs_cache_pressure=%s\n" "$CURRENT_SWAP" "$CURRENT_PRES"
    printf "   冲突的配置文件路径:\n"
    for file in $CONF_FILES; do
        printf "   📄 %s\n" "$file"
    done
    printf "   ----------------------------------------\n"
    
    if [ "$AUTO_MODE" = "true" ]; then
        printf "🚀 已启用无人值守模式，将自动清理旧冲突并覆盖。\n"
        OVERWRITE_CHOICE="y"
    else
        printf "是否清理旧的冲突配置并强行覆盖？[y/n, 默认 y]: "
        read -r OVERWRITE_CHOICE
        : ${OVERWRITE_CHOICE:="y"}
    fi
    
    if [ "$OVERWRITE_CHOICE" = "y" ] || [ "$OVERWRITE_CHOICE" = "Y" ]; then
        printf "🧹 正在清理旧配置文件中的冲突行...\n"
        for file in $CONF_FILES; do
            sudo cp "$file" "${file}.bak"
            sudo sed -i '/^vm.swappiness/d' "$file"
            sudo sed -i '/^vm.vfs_cache_pressure/d' "$file"
        done
        printf "✅ 旧冲突清理完毕（已为您自动生成 .bak 备份文件）。\n"
    else
        printf "❌ 用户取消操作，脚本停止。\n"
        exit 0
    fi
else
    printf "ℹ️ 系统环境纯净，未发现任何内核参数冲突。\n"
fi
printf "\n"

TOTAL_RAM_KB=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
TOTAL_RAM=$((TOTAL_RAM_KB / 1024))
printf "ℹ️ 总物理内存: %s MB\n" "$TOTAL_RAM"

if [ "$TOTAL_RAM" -le 1024 ]; then sw=60; pr=100;
elif [ "$TOTAL_RAM" -le 2048 ]; then sw=30; pr=80;
elif [ "$TOTAL_RAM" -le 4096 ]; then sw=15; pr=70;
else sw=10; pr=60; fi

if [ "$AUTO_MODE" = "true" ]; then
    USER_SWAPPINESS=$sw
    USER_PRESSURE=$pr
else
    printf "请选择场景: [1] 纯 Xray 节点  [2] 复合服务器(Docker/Web/数据库) [默认 2]\n"
    printf "选择: "
    read -r choice
    if [ "$choice" = "1" ]; then
        if [ "$TOTAL_RAM" -le 1024 ]; then sw=60; pr=120; else sw=20; pr=100; fi
    fi
    
    printf "💡 推荐值: swappiness=%s, vfs_cache_pressure=%s\n" "$sw" "$pr"
    printf "请输入 vm.swappiness [%s]: " "$sw"
    read -r USER_SWAPPINESS
    : ${USER_SWAPPINESS:=$sw}
    printf "请输入 vm.vfs_cache_pressure [%s]: " "$pr"
    read -r USER_PRESSURE
    : ${USER_PRESSURE:=$pr}
fi

printf "正在分配空间 (%s)...\n" "$SWAP_SIZE"
if ! sudo fallocate -l "$SWAP_SIZE" "$SWAP_PATH" 2>/dev/null; then
    printf "ℹ️ fallocate 不受文件系统支持，正在降级使用 dd 擦写分配...\n"
    CLEAN_SIZE=$(echo "$SWAP_SIZE" | tr -cd '0-9')
    sudo dd if=/dev/zero of="$SWAP_PATH" bs=1M count="$CLEAN_SIZE" status=progress
fi

sudo chmod 600 "$SWAP_PATH"
sudo mkswap "$SWAP_PATH"
sudo swapon "$SWAP_PATH"

if ! grep -q "$SWAP_PATH" /etc/fstab; then
    printf "%s   none    swap    sw    0   0\n" "$SWAP_PATH" | sudo tee -a /etc/fstab
fi

if [ ! -d "/etc/sysctl.d" ]; then sudo mkdir -p /etc/sysctl.d; fi

sudo bash -c "cat << EOF > $SYSCTL_CONF
# Optimized by Script
vm.swappiness = $USER_SWAPPINESS
vm.vfs_cache_pressure = $USER_PRESSURE
EOF"

sudo sysctl --system >/dev/null 2>&1

## ==================== 自检健康报告 (POSIX printf 升级版) ====================
printf "\n"
printf "==================================================\n"
printf "          📊 SWAP 部署成果自检健康报告            \n"
printf "==================================================\n"

CHECK_SWAP_ACTIVE=$(swapon --show=NAME --noheadings | grep -w "$SWAP_PATH")
if [ -n "$CHECK_SWAP_ACTIVE" ]; then
    SWAP_REAL_SIZE=$(free -h | awk '/^Swap:/{print $2}')
    printf "  [物理挂载]：\033[32m正常生效 (Active)\033[0m\n"
    printf "  [当前总Swap容量]：\033[36m%s\033[0m\n" "$SWAP_REAL_SIZE"
else
    printf "  [物理挂载]：\033[31m异常失败 (Not Found)\033[0m\n"
fi

FINAL_SWAP=$(sysctl -n vm.swappiness 2>/dev/null)
FINAL_PRES=$(sysctl -n vm.vfs_cache_pressure 2>/dev/null)

printf "  [内核实时参数]：\n"
if [ "$FINAL_SWAP" = "$USER_SWAPPINESS" ]; then
    printf "    - vm.swappiness = %s  (\033[32m已成功同步\033[0m)\n" "$FINAL_SWAP"
else
    printf "    - vm.swappiness = %s  (\033[31m异常：与设定值 %s 不符\033[0m)\n" "$FINAL_SWAP" "$USER_SWAPPINESS"
fi

if [ "$FINAL_PRES" = "$USER_PRESSURE" ]; then
    printf "    - vm.vfs_cache_pressure = %s  (\033[32m已成功同步\033[0m)\n" "$FINAL_PRES"
fi

if grep -q "$SWAP_PATH" /etc/fstab; then
    printf "  [开机自动挂载]：\033[32m已成功固化到 fstab\033[0m\n"
else
    printf "  [开机自动挂载]：\033[31m未发现固化配置，重启后将失效\033[0m\n"
fi
printf "==================================================\n"
printf "🎉 部署与检查全部完成！\n"
