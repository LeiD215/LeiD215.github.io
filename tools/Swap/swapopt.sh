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
SYSCTL_CONF="/etc/sysctl.d/99-dleia-swapopt.conf"

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
    
    if [ -f "$SYSCTL_CONF" ]; then
        sudo rm -f $SYSCTL_CONF
        sudo sysctl --system >/dev/null 2>&1
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
elif [ "$TOTAL_RAM" -le 2048 ]; then sw=30; pr=80;  stage="2G内存 复合Web";
elif [ "$TOTAL_RAM" -le 4096 ]; then sw=15; pr=70;  stage="4G内存 黄金平衡";
else sw=10; pr=60; stage="8G以上 高性能"; fi

if [ "$AUTO_MODE" = "true" ]; then
    USER_SWAPPINESS=$sw
    USER_PRESSURE=$pr
else
    echo "请选择场景: [1] 纯 Xray 节点  [2] 复合服务器(Docker/Web/数据库) [默认 2]"
    read -p "选择: " choice
    if [ "$choice" = "1" ]; then
        if [ "$TOTAL_RAM" -le 1024 ]; then sw=60; pr=120; else sw=20; pr=100; fi
    fi
    
    echo "💡 推荐值: swappiness=$sw, vfs_cache_pressure=$pr"
    read -p "请输入 vm.swappiness [$sw]: " USER_SWAPPINESS
    : ${USER_SWAPPINESS:=$sw}
    read -p "请输入 vm.vfs_cache_pressure [$pr]: " USER_PRESSURE
    : ${USER_PRESSURE:=$pr}
fi

# 3. 核心执行：分配实体物理空间
echo "正在分配空间 ($SWAP_SIZE)..."
if ! sudo fallocate -l $SWAP_SIZE $SWAP_PATH 2>/dev/null; then
    echo "ℹ️ fallocate 不受文件系统支持，正在降级使用 dd 擦写分配..."
    CLEAN_SIZE=$(echo $SWAP_SIZE | tr -cd '0-9')
    sudo dd if=/dev/zero of=$SWAP_PATH bs=1M count=$CLEAN_SIZE status=progress
fi

sudo chmod 600 $SWAP_PATH
sudo mkswap $SWAP_PATH
sudo swapon $SWAP_PATH

# 去重写入 fstab 开机自动挂载
if ! grep -q "$SWAP_PATH" /etc/fstab; then
    echo "$SWAP_PATH   none    swap    sw    0   0" | sudo tee -a /etc/fstab
fi

# 4. 写入独立配置文件
if [ ! -d "/etc/sysctl.d" ]; then
    sudo mkdir -p /etc/sysctl.d
fi

sudo bash -c "cat << EOF > $SYSCTL_CONF
# Optimized by Script
vm.swappiness = $USER_SWAPPINESS
vm.vfs_cache_pressure = $USER_PRESSURE
EOF"

sudo sysctl --system >/dev/null 2>&1

## ==================== 新增：自动化成果健康检查报告 ====================
echo
echo "=================================================="
echo "          📊 SWAP 部署成果自检健康报告            "
echo "=================================================="

# 验证 1：实体挂载状态验证
CHECK_SWAP_ACTIVE=$(swapon --show=NAME --noheadings | grep -w "$SWAP_PATH")
if [ ! -z "$CHECK_SWAP_ACTIVE" ]; then
    SWAP_REAL_SIZE=$(free -h | awk '/^Swap:/{print $2}')
    echo -e "  [物理挂载]：\033[32m正常生效 (Active)\033[0m"
    echo -e "  [当前总Swap容量]：\033[36m$SWAP_REAL_SIZE\033[0m"
else
    echo -e "  [物理挂载]：\033[31m异常失败 (Not Found)\033[0m"
fi

# 验证 2：内核策略生效值验证
FINAL_SWAP=$(sysctl -n vm.swappiness 2>/dev/null)
FINAL_PRES=$(sysctl -n vm.vfs_cache_pressure 2>/dev/null)

echo -e "  [内核实时参数]："
if [ "$FINAL_SWAP" = "$USER_SWAPPINESS" ]; then
    echo -e "    - vm.swappiness = $FINAL_SWAP  (\033[32m已成功同步\033[0m)"
else
    echo -e "    - vm.swappiness = $FINAL_SWAP  (\033[31m异常：与设定值 $USER_SWAPPINESS 不符\033[0m)"
fi

if [ "$FINAL_PRES" = "$USER_PRESSURE" ]; then
    echo -e "    - vm.vfs_cache_pressure = $FINAL_PRES  (\033[32m已成功同步\033[0m)"
else
    echo -e "    - vm.vfs_cache_pressure = $FINAL_PRES  (\033[31m异常：与设定值 $USER_PRESSURE 不符\033[0m)"
fi

# 验证 3：开机自启固化验证
if grep -q "$SWAP_PATH" /etc/fstab; then
    echo -e "  [开机自动挂载]：\033[32m已成功固化到 fstab\033[0m"
else
    echo -e "  [开机自动挂载]：\033[31m未发现固化配置，重启后将失效\033[0m"
fi
echo "=================================================="
echo "🎉 部署与检查全部完成！"
