#!/bin/bash

# ==============================================================================
# 🛡️ Linux 自动化防火墙安全管理脚本 (高级综合完美版)
# 支持系统: CentOS, Debian, Ubuntu, Rocky Linux, AlmaLinux 等
# 功能特性: 自动识别OS、解冲突卸载、保留现存无缝接管、SSH防锁死、
#           内外网端口转发、IPv4/IPv6 双栈智能内核转发配置。
# ==============================================================================

# 确保以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "❌ 错误: 请使用 root 权限运行此脚本！(例如: sudo bash $0)"
    exit 1
fi

# ==========================================
# 1. 系统环境与已安装防火墙检测
# ==========================================
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME=$ID
        OS_VERSION=$VERSION_ID
    else
        echo "❌ 错误: 无法检测到系统发行版类型，脚本退出。"
        exit 1
    fi

    # 规范化系统大类
    case "$OS_NAME" in
        ubuntu|debian)
            OS_FAMILY="debian"
            ;;
        centos|rhel|rocky|almalinux)
            OS_FAMILY="rhel"
            ;;
        *)
            echo "⚠️ 警告: 暂未官方支持的系统类型 ($OS_NAME)，脚本尝试按 Debian 兼容模式继续。"
            OS_FAMILY="debian"
            ;;
    esac
    echo "🌐 [系统环境] 检测到 OS: ${OS_NAME} | 版本: ${OS_VERSION} | 归属系列: ${OS_FAMILY^^}"
}

check_installed_firewalls() {
    HAS_UFW=false
    HAS_FIREWALLD=false
    
    command -v ufw >/dev/null 2>&1 && HAS_UFW=true
    command -v firewall-cmd >/dev/null 2>&1 && HAS_FIREWALLD=true

    echo "🔍 [组件检查] 正在扫描现有防火墙状态："
    $HAS_UFW && echo "  -> [已安装] UFW (Uncomplicated Firewall)" || echo "  -> [未安装] UFW"
    $HAS_FIREWALLD && echo "  -> [已安装] Firewalld" || echo "  -> [未安装] Firewalld"
}

# ==========================================
# 2. 交互式卸载与全新安装（已升级智能跳过逻辑）
# ==========================================
manage_installation() {
    local skipped_install=false

    # 询问卸载已有防火墙（解除潜在冲突）
    if [ "$HAS_UFW" = true ] || [ "$HAS_FIREWALLD" = true ]; then
        echo "------------------------------------------"
        read -p "❓ 检测到系统已存在防火墙组件，是否需要执行彻底卸载并清理残留规则？(y/n): " choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            if [ "$HAS_UFW" = true ]; then
                echo "🗑️ 正在强力卸载 UFW 并清除其规则缓存..."
                ufw disable >/dev/null 2>&1
                if [ "$OS_FAMILY" = "debian" ]; then
                    apt-get remove --purge -y ufw >/dev/null 2>&1
                else
                    yum remove -y ufw >/dev/null 2>&1
                fi
            fi
            if [ "$HAS_FIREWALLD" = true ]; then
                echo "🗑️ 正在停止并卸载 Firewalld..."
                systemctl stop firewalld >/dev/null 2>&1
                systemctl disable firewalld >/dev/null 2>&1
                if [ "$OS_FAMILY" = "rhel" ]; then
                    yum remove -y firewalld >/dev/null 2>&1
                else
                    apt-get remove --purge -y firewalld >/dev/null 2>&1
                fi
            fi
            # 清理通用 iptables 规则防止锁死或冲突
            iptables -F >/dev/null 2>&1
            iptables -X >/dev/null 2>&1
            ip6tables -F >/dev/null 2>&1 2>/dev/null
            echo "✅ 历史防火墙组件及其残留规则已成功清理。"
            HAS_UFW=false
            HAS_FIREWALLD=false
        else
            # 【智能识别点】：如果用户选择不卸载，且系统里恰好只有一个防火墙在运行，直接接管并跳过后续菜单
            if [ "$HAS_UFW" = true ] && [ "$HAS_FIREWALLD" = false ]; then
                CURRENT_FW="ufw"
                skipped_install=true
                echo "💡 您选择了保留现有的 UFW 防火墙，脚本将直接对其进行接管与配置。"
            elif [ "$HAS_FIREWALLD" = true ] && [ "$HAS_UFW" = false ]; then
                CURRENT_FW="firewalld"
                skipped_install=true
                echo "💡 您选择了保留现有的 Firewalld 防火墙，脚本将直接对其进行接管与配置。"
            fi
        fi
    fi

    # 如果满足跳过条件，直接退出本函数，不再弹出无意义的安装菜单
    if [ "$skipped_install" = true ]; then
        return
    fi

    # 交互询问安装哪种防火墙（仅在彻底没有防火墙或冲突时触发）
    echo "------------------------------------------"
    echo "💡 请选择您接下来想要安装并管理的防火墙工具："
    echo "1) UFW (强烈推荐 Debian / Ubuntu 用户)"
    echo "2) Firewalld (强烈推荐 CentOS / RHEL / Rocky / Alma 用户)"
    echo "3) 退出脚本（不作变更）"
    read -p "请输入序列号 (1-3): " install_choice

    case $install_choice in
        1)
            echo "📥 正在为您安装 UFW 防火墙..."
            if [ "$OS_FAMILY" = "debian" ]; then
                apt-get update && apt-get install -y ufw
            else
                yum install -y epel-release && yum install -y ufw
            fi
            CURRENT_FW="ufw"
            echo "✅ 新防火墙系统 (UFW) 安装并启动成功。"
            ;;
        2)
            echo "📥 正在为您安装 Firewalld 防火墙..."
            if [ "$OS_FAMILY" = "rhel" ]; then
                yum install -y firewalld
            else
                apt-get update && apt-get install -y firewalld
            fi
            systemctl unmask firewalld >/dev/null 2>&1
            systemctl enable --now firewalld
            CURRENT_FW="firewalld"
            echo "✅ 新防火墙系统 (FIREWALLD) 安装并启动成功。"
            ;;
        *)
            echo "👋 您选择了退出。未做任何变更，再见！"
            exit 0
            ;;
    esac
}

# ==========================================
# 3. SSH 端口智能检测与防御初始化
# ==========================================
init_ssh_security() {
    echo "------------------------------------------"
    echo "🛡️ 正在启动 [SSH 安全初始化防御拦截] 机制..."
    
    # 精准读取系统当前真实监听的 SSH 端口 (排除注释行，提取Port字段或监听状态)
    SSH_PORT=$(ss -tlnp | grep -E 'sshd|"sshd"' | awk '{print $4}' | awk -F':' '{print $nf}' | sort -nu | head -n1)
    if [ -z "$SSH_PORT" ]; then
        # 备用方案：通过 sshd_config 配置文件解析
        SSH_PORT=$(grep -E -i "^\s*Port\s+" /etc/ssh/sshd_config | awk '{print $2}' | head -n1)
        [ -z "$SSH_PORT" ] && SSH_PORT=22 # 最终兜底默认22
    fi

    read -p "🤖 智能检测到当前 SSH 端口可能是 [ $SSH_PORT ]。请按回车确认，或直接输入您的实际 SSH 端口: " user_port
    if [ ! -z "$user_port" ]; then
        SSH_PORT=$user_port
    fi

    echo "🔒 安全策略执行中：默认拒绝所有外部入站流量，
    
