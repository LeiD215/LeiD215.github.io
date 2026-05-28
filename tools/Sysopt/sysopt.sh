#!/bin/sh

# =================================================================
#  系统级网络与资源自适应优化脚本 (POSIX sh 100% 兼容完全体版)
#  适用场景：Xray节点 + Remnawave多节点管理 + Docker + 数据库Web服务器
#  全面兼容：CentOS 7-9, Debian 9-13, Ubuntu 18-24 
# =================================================================

# 颜色与图标定义 (采用 printf 标准转义，拒绝 dash/bash 歧义)
INFO="\033[36m[ℹ️]\033[0m"
SUCCESS="\033[32m[🎉]\033[0m"
ERROR="\033[31m[❌]\033[0m"
WARN="\033[33m[⚠️]\033[0m"

SYSCTL_CONF="/etc/sysctl.d/95-dleia-sysopt.conf"
AUTO_MODE=false
UNINSTALL_MODE=false

# 打印帮助信息
show_help() {
    printf "使用方法:\n"
    printf "  新建优化:   $0 [--auto|-y]\n"
    printf "  卸载优化:   $0 --uninstall\n"
    printf "例如:\n"
    printf "  $0                  (交互式运行网络与系统资源优化)\n"
    printf "  $0 -y               (无人值守自动一键全盘优化)\n"
    printf "  $0 --uninstall      (一键卸载优化文件，恢复系统默认限制)\n"
    exit 1
}

# 参数解析 (完全兼容纯 sh 语法)
for arg in "$@"; do
    case $arg in
        --uninstall) UNINSTALL_MODE=true ;;
        --auto|-y) AUTO_MODE=true ;;
        *) show_help ;;
    esac
done

optimizing_system() {
    ## ==================== 卸载模式 ====================
    if [ "$UNINSTALL_MODE" = "true" ]; then
        printf "%b 开始卸载系统网络与资源限制优化...\n" "$INFO"
        
        if [ -f "$SYSCTL_CONF" ]; then
            sudo rm -f "$SYSCTL_CONF"
            printf "%b 已删除内核网络参数配置文件: %s\n" "$SUCCESS" "$SYSCTL_CONF"
        else
            printf "%b 未发现自定义内核参数优化文件，无需处理。\n" "$INFO"
        fi
        
        if [ -f "/etc/systemd/system.conf.bak" ]; then
            sudo mv /etc/systemd/system.conf.bak /etc/systemd/system.conf
            sudo systemctl daemon-reload >/dev/null 2>&1
            printf "%b 已还原 Systemd 全局资源限制配置。\n" "$SUCCESS"
        fi
        
        if [ -f "/etc/security/limits.conf.bak" ]; then
            sudo mv /etc/security/limits.conf.bak /etc/security/limits.conf
            printf "%b 已还原安全控制 limits.conf 文件描述符限制。\n" "$SUCCESS"
        fi

        if [ -f "/etc/profile" ]; then
            sudo sed -i '/ulimit -SHn/d' /etc/profile
            sudo sed -i '/ulimit -SHu/d' /etc/profile
        fi

        sudo sysctl --system >/dev/null 2>&1
        printf "%b 卸载完成！内核及资源参数已完美恢复系统原生状态。\n" "$SUCCESS"
        exit 0
    fi

    ## ==================== 优化模式 ====================
    printf "%b 开始进行系统级网络与复合业务优化 (自适应 CPU/内存/内核版本)...\n" "$INFO"

    if [ -f /proc/meminfo ]; then
        total_mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
        total_mem_mb=$((total_mem_kb / 1024))
    else
        total_mem_mb=$(free -m | awk '/^Mem:/{print $2}')
    fi

    cpu_cores=$(nproc 2>/dev/null || echo 1)
    kernel_major=$(uname -r | cut -d. -f1)
    kernel_minor=$(uname -r | cut -d. -f2)

    current_cc=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || echo "bbr")
    current_qdisc=$(cat /proc/sys/net/core/default_qdisc 2>/dev/null || echo "fq")
    if [ "$current_cc" = "unknown" ] || [ -z "$current_cc" ]; then current_cc="bbr"; fi
    if [ "$current_qdisc" = "unknown" ] || [ -z "$current_qdisc" ]; then current_qdisc="fq"; fi

    local_tcp_mem_max=16777216
    local_rmem_def=65536
    local_wmem_def=65536
    local_somaxconn=1024
    local_file_max=131072
    machine_stage="1G 极限生存机型"

    if [ "$total_mem_mb" -ge 8192 ]; then
        local_tcp_mem_max=67108864 
        local_rmem_def=262144      
        local_wmem_def=262144
        local_somaxconn=10240      
        local_file_max=1048576     
        machine_stage="8G+ 高性能机型"
    elif [ "$total_mem_mb" -ge 4096 ]; then
        local_tcp_mem_max=33554432 
        local_rmem_def=131072      
        local_wmem_def=131072
        local_somaxconn=4096
        local_file_max=524288
        machine_stage="4G 黄金平衡机型"
    elif [ "$total_mem_mb" -ge 2048 ]; then
        local_tcp_mem_max=25165824 
        local_rmem_def=87380       
        local_wmem_def=65536
        local_somaxconn=2048
        local_file_max=262144
        machine_stage="2G/3G 中等复合机型"
    fi

    printf "%b 检测到物理内存: %s MB, CPU核心数: %s 核\n" "$INFO" "$total_mem_mb" "$cpu_cores"
    printf "%b 脚本自动为您适配策略为: [%s]\n" "$INFO" "$machine_stage"

    local_netdev_max_backlog=$((2048 * cpu_cores))
    if [ "$local_netdev_max_backlog" -lt 4096 ]; then local_netdev_max_backlog=4096; fi
    if [ "$local_netdev_max_backlog" -gt 16384 ]; then local_netdev_max_backlog=16384; fi
    local_netdev_budget=$((300 + 20 * cpu_cores))

    if [ "$AUTO_MODE" = "false" ]; then
        printf "%b 即将执行全盘网络调优并放开系统高并发文件描述符上限。\n" "$INFO"
        printf "是否继续执行优化？[y/n, 默认 y]: "
        read -r USER_CHOICE
        : ${USER_CHOICE:="y"}
        if [ "$USER_CHOICE" != "y" ] && [ "$USER_CHOICE" != "Y" ]; then
            printf "%b 用户取消，脚本安全退出。\n" "$WARN"
            exit 0
        fi
    fi

    if [ ! -d "/etc/sysctl.d" ]; then sudo mkdir -p /etc/sysctl.d; fi

    [ -f "$SYSCTL_CONF" ] && sudo cp "$SYSCTL_CONF" "${SYSCTL_CONF}.bak"
    sudo cat /dev/null > "$SYSCTL_CONF"

    sudo touch /etc/sysctl.conf
    sudo sed -i '/fs.file-max/d' /etc/sysctl.conf
    sudo sed -i '/net.core.somaxconn/d' /etc/sysctl.conf

    sudo bash -c "cat >> '$SYSCTL_CONF' <<EOF
# --- 文件系统与进程限制 ---
fs.file-max = $local_file_max
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = $local_file_max

# --- 网络核心队列与连接数 ---
net.core.somaxconn = $local_somaxconn
net.core.netdev_max_backlog = $local_netdev_max_backlog
net.core.netdev_budget = $local_netdev_budget
net.core.rmem_max = $local_tcp_mem_max
net.core.wmem_max = $local_tcp_mem_max
net.core.rmem_default = $local_rmem_def
net.core.wmem_default = $local_wmem_def
net.core.optmem_max = 65536

# --- TCP 核心调优 (缓冲区自适应) ---
net.ipv4.tcp_rmem = 4096 87380 $local_tcp_mem_max
net.ipv4.tcp_wmem = 4096 65536 $local_tcp_mem_max
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_autocorking = 0
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_max_syn_backlog = $local_somaxconn
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_no_metrics_save = 0
net.ipv4.tcp_ecn = 1
net.ipv4.tcp_ecn_fallback = 1
net.ipv4.tcp_frto = 0

# --- TCP 超时、重传与 KeepAlive 优化 ---
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 2
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_synack_retries = 1
net.ipv4.tcp_orphan_retries = 1
net.ipv4.tcp_retries2 = 5
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 0
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3

# --- 路由转发与 IPv6 ---
net.ipv4.ip_forward = 1
net.ipv4.conf.all.route_localnet = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.default.forwarding = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
net.ipv6.conf.lo.forwarding = 1
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0

# --- 默认拥塞控制 ---
net.core.default_qdisc = $current_qdisc
net.ipv4.tcp_congestion_control = $current_cc
EOF"

    if [ "$kernel_major" -lt 4 ] || { [ "$kernel_major" -eq 4 ] && [ "$kernel_minor" -lt 12 ]; }; then
        sudo bash -c "echo 'net.ipv4.tcp_tw_recycle = 0' >> '$SYSCTL_CONF'"
    fi
    if [ "$kernel_major" -lt 4 ] || { [ "$kernel_major" -eq 4 ] && [ "$kernel_minor" -lt 11 ]; }; then
        sudo bash -c "echo 'net.ipv4.tcp_fack = 1' >> '$SYSCTL_CONF'"
    fi

    printf "%b 正在优化系统全局文件描述符与 Systemd 资源吞吐限制...\n" "$INFO"

    if [ -d "/etc/systemd" ]; then
        [ ! -f "/etc/systemd/system.conf.bak" ] && sudo cp /etc/systemd/system.conf /etc/systemd/system.conf.bak
        sudo bash -c "cat > /etc/systemd/system.conf <<EOF
[Manager]
DefaultTimeoutStopSec=30s
DefaultLimitCORE=infinity
DefaultLimitNOFILE=$local_file_max
DefaultLimitNPROC=infinity
DefaultTasksMax=infinity
EOF"
        sudo systemctl daemon-reload >/dev/null 2>&1
    fi

    if [ -d "/etc/security" ]; then
        [ ! -f "/etc/security/limits.conf.bak" ] && sudo cp /etc/security/limits.conf /etc/security/limits.conf.bak
        sudo bash -c "cat > /etc/security/limits.conf <<EOF
* soft   nofile    $local_file_max
* hard   nofile    $local_file_max
* soft   nproc     unlimited
* hard   nproc     unlimited
* soft   core      unlimited
* hard   core      unlimited
root  soft   nofile    $local_file_max
root  hard   nofile    $local_file_max
root  soft   nproc     unlimited
root  hard   nproc     unlimited
root  soft   core      unlimited
root  hard   core      unlimited
EOF"
    fi

    sudo sed -i '/ulimit -SHn/d' /etc/profile
    sudo sed -i '/ulimit -SHu/d' /etc/profile

    if [ -f "/etc/pam.d/common-session" ] && ! grep -q "pam_limits.so" /etc/pam.d/common-session; then
        sudo bash -c "echo 'session required pam_limits.so' >> /etc/pam.d/common-session"
    fi

    printf "%b 正在应用自适应内核网络参数...\n" "$INFO"
    sudo sysctl --system >/dev/null 2>&1

    if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
        sudo bash -c "echo always > /sys/kernel/mm/transparent_hugepage/enabled"
    fi

    ## ==================== 自检健康报告 (POSIX printf 升级版) ====================
    printf "\n"
    printf "==================================================\n"
    printf "         📊 SYSOPT 网络与资源自检健康报告          \n"
    printf "==================================================\n"

    FINAL_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    FINAL_QDISC=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    printf "  [拥塞控制算法]：\033[32m%s\033[0m  (队列规则: \033[36m%s\033[0m)\n" "$FINAL_CC" "$FINAL_QDISC"

    FINAL_FMAX=$(sysctl -n fs.file-max 2>/dev/null)
    FINAL_CONN=$(sysctl -n net.core.somaxconn 2>/dev/null)
    FINAL_RDEF=$(sysctl -n net.core.rmem_default 2>/dev/null)

    printf "  [内核自适应参数]：\n"
    if [ "$FINAL_FMAX" = "$local_file_max" ]; then
        printf "    - fs.file-max = %s  (\033[32m已成功同步\033[0m)\n" "$FINAL_FMAX"
    else
        printf "    - fs.file-max = %s  (\033[31m未同步：当前为系统默认值\033[0m)\n" "$FINAL_FMAX"
    fi

    if [ "$FINAL_CONN" = "$local_somaxconn" ]; then
        printf "    - net.core.somaxconn = %s  (\033[32m已成功同步\033[0m)\n" "$FINAL_CONN"
    else
        printf "    - net.core.somaxconn = %s  (\033[31m未同步\033[0m)\n" "$FINAL_CONN"
    fi

    if [ "$FINAL_RDEF" = "$local_rmem_def" ]; then
        printf "    - net.core.rmem_default = %s  (\033[32m安全阈值锁定\033[0m)\n" "$FINAL_RDEF"
    else
        printf "    - net.core.rmem_default = %s  (\033[33m系统自适应托管中\033[0m)\n" "$FINAL_RDEF"
    fi

    if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
        THP_STATUS=$(cat /sys/kernel/mm/transparent_hugepage/enabled | grep -o '\[.*\]')
        if [ "$THP_STATUS" = "[always]" ]; then
            printf "  [透明大页加速]：\033[32m已开启 (Always) -> 正在为多节点管理提速\033[0m\n"
        else
            printf "  [透明大页加速]：\033[33m当前状态 %s\033[0m\n" "$THP_STATUS"
        fi
    fi

    if grep -q "root  hard   nofile    $local_file_max" /etc/security/limits.conf 2>/dev/null; then
        printf "  [系统级并发破除]：\033[32mlimits.conf 最大文件描述符已放开至 %s\033[0m\n" "$local_file_max"
    else
        printf "  [系统级并发破除]：\033[31mlimits.conf 未配置，高并发下可能触发报错\033[0m\n"
    fi
    printf "==================================================\n"
    printf "%b 系统级网络与并发资源自适应优化部署成功！\n" "$SUCCESS"
    printf "%b 建议在完成后续所有配置后，执行一次 [reboot] 重启服务器以完全释放资源限制。\n" "$INFO"
}

optimizing_system
