#!/bin/bash

# ==============================================================================
# 🛡️ Linux 自动化防火墙安全管理脚本 (高级综合完美版 v2.1)
# 支持系统: CentOS, Debian, Ubuntu, Rocky Linux, AlmaLinux 等
# 功能特性: 自动识别OS、解冲突卸载、保留现存无缝接管、SSH防锁死(纯数字高精修复)、
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
# 2. 交互式卸载与全新安装
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
            # 如果用户选择不卸载，直接锁定管理目标并跳过安装菜单
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

    # 如果满足跳过条件，直接退出本函数
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
# 3. SSH 端口智能检测与防御初始化 (高精防错升级)
# ==========================================
init_ssh_security() {
    echo "------------------------------------------"
    echo "🛡️ 正在启动 [SSH 安全初始化防御拦截] 机制..."
    
    # 强力升级：精准提取纯数字端口，彻底过滤 0.0.0.0: 或 [::]: 干扰
    SSH_PORT=$(ss -tlnp | grep -E 'sshd|"sshd"' | awk '{print $4}' | awk -F':' '{print $NF}' | tr -d ']' | sort -nu | head -n1)
    
    if [ -z "$SSH_PORT" ] || ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]]; then
        # 备用方案：通过 sshd_config 配置文件解析
        SSH_PORT=$(grep -E -i "^\s*Port\s+" /etc/ssh/sshd_config | awk '{print $2}' | head -n1)
        [ -z "$SSH_PORT" ] && SSH_PORT=22
    fi

    echo "🤖 智能检测到当前真实 SSH 端口为: [ $SSH_PORT ]"
    read -p "   请按回车直接确认，或者输入您修改过的实际 SSH 端口: " user_port
    if [ ! -z "$user_port" ]; then
        SSH_PORT=$user_port
    fi

    # 再次做最终纯数字合法性校验，防止由于任何意外导致放行空规则而锁死
    if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]]; then
        echo "❌ 错误: 最终识别到的端口 [$SSH_PORT] 不是合法的纯数字，为防锁死，放弃初始化！"
        return 1
    fi

    echo "🔒 安全策略执行中：默认拒绝所有外部入站流量，仅放行确认的 SSH 端口 ($SSH_PORT)..."
    
    if [ "$CURRENT_FW" = "ufw" ]; then
        ufw disable >/dev/null 2>&1
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow "$SSH_PORT"/tcp comment 'SSH Port Auto Allowed'
        echo "y" | ufw enable >/dev/null
    elif [ "$CURRENT_FW" = "firewalld" ]; then
        local zone=$(firewall-cmd --get-default-zone)
        firewall-cmd --permanent --zone="$zone" --remove-service=ssh >/dev/null 2>&1
        firewall-cmd --permanent --zone="$zone" --add-port="$SSH_PORT"/tcp
        firewall-cmd --reload >/dev/null
    fi
    
    echo "=================================================================="
    echo "✅ 防火墙安全初始化成功！当前规则：【默认阻断所有，仅开放 SSH 端口: $SSH_PORT】"
    echo "⚠️  【紧急安全提醒】: 请切勿关闭当前的 SSH 终端窗口！"
    echo "    请立即新建一个独立的终端窗口尝试重新连接本服务器，确保 SSH 未被锁死！"
    echo "=================================================================="
}

# ==========================================
# 4. 双栈内核转发智能使能
# ==========================================
enable_ip_forwarding() {
    if [ "$IP_VER" = "4" ] || [ "$IP_VER" = "both" ]; then
        if [ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" -ne 1 ]; then
            echo "🌐 检测到系统内核未开启 IPv4 数据包转发，正在为您使能..."
            sysctl -w net.ipv4.ip_forward=1 >/dev/null
            grep -q "net.ipv4.ip_forward" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
        fi
    fi

    if [ "$IP_VER" = "6" ] || [ "$IP_VER" = "both" ]; then
        if [ "$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null)" -ne 1 ]; then
            echo "🌐 检测到系统内核未开启 IPv6 数据包转发，正在为您使能..."
            sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null
            grep -q "net.ipv6.conf.all.forwarding" /etc/sysctl.conf || echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
            
            # 健壮性加固：防止动态机房网络因开启转发而丢失公网 IPv6
            sysctl -w net.ipv6.conf.all.accept_ra=2 >/dev/null 2>&1
            grep -q "net.ipv6.conf.all.accept_ra" /etc/sysctl.conf || echo "net.ipv6.conf.all.accept_ra=2" >> /etc/sysctl.conf
        fi
    fi
    sysctl -p >/dev/null 2>&1
}

# ==========================================
# 5. 模块化通用多选交互函数
# ==========================================
choose_proto() {
    echo "----------------------------------"
    echo "👉 请选择要绑定的网络协议："
    echo "1) TCP"
    echo "2) UDP"
    echo "3) TCP + UDP (两者都要)"
    read -p "选择 (默认 1): " p_choice
    case $p_choice in
        2) PROTO="udp" ;;
        3) PROTO="both" ;;
        *) PROTO="tcp" ;;
    esac
    echo "Selected: ${PROTO^^}"
}

choose_ip_version() {
    echo "----------------------------------"
    echo "👉 请选择要适用的 IP 栈版本："
    echo "1) IPv4"
    echo "2) IPv6"
    echo "3) IPv4 + IPv6 (两者都要)"
    read -p "选择 (默认 1): " ip_choice
    case $ip_choice in
        2) IP_VER="6" ;;
        3) IP_VER="both" ;;
        *) IP_VER="4" ;;
    esac
    echo "Selected: IP v${IP_VER}"
}

# ==========================================
# 6. 核心业务功能：基础端口开放与关闭
# ==========================================
manage_ports() {
    echo "------------------------------------------"
    echo "▶️  [功能：端口开放与关闭管理]"
    echo "1) 开放特定端口"
    echo "2) 阻止/关闭特定端口"
    read -p "请选择操作 (1-2): " op_choice
    read -p "请输入要操作的端口号 (单个如 80，连续范围如 8000:8010): " port
    
    if [ -z "$port" ]; then
        echo "❌ 错误: 端口号不能为空！"
        return
    fi
    
    choose_proto
    choose_ip_version

    local action="allow"
    [ "$op_choice" = "2" ] && action="deny"

    local protos=("$PROTO")
    [ "$PROTO" = "both" ] && protos=("tcp" "udp")

    if [ "$CURRENT_FW" = "ufw" ]; then
        for p in "${protos[@]}"; do
            if [ "$IP_VER" = "4" ]; then
                ufw $action proto $p from any to any port $port
            elif [ "$IP_VER" = "6" ]; then
                ufw $action proto $p from v6 any to any port $port
            else
                ufw $action proto $p port $port
            fi
        done
        ufw reload >/dev/null
    elif [ "$CURRENT_FW" = "firewalld" ]; then
        local zone=$(firewall-cmd --get-default-zone)
        local fw_action="--add-port"
        [ "$op_choice" = "2" ] && fw_action="--remove-port"
        
        for p in "${protos[@]}"; do
            if [ "$IP_VER" = "4" ]; then
                firewall-cmd --permanent --zone="$zone" --add-rich-rule="rule family='ipv4' port port='$port' protocol='$p' accept" 2>/dev/null || firewall-cmd --permanent --zone="$zone" $fw_action="$port"/$p
            elif [ "$IP_VER" = "6" ]; then
                firewall-cmd --permanent --zone="$zone" --add-rich-rule="rule family='ipv6' port port='$port' protocol='$p' accept"
            else
                firewall-cmd --permanent --zone="$zone" $fw_action="$port"/$p
            fi
        done
        firewall-cmd --reload >/dev/null
    fi
    echo "✅ 端口操作执行成功！操作: [${action^^}], 端口: [$port], 协议: [${PROTO^^}]"
}

# ==========================================
# 7. 核心业务功能：端口转发 (支持双栈与多场景)
# ==========================================
manage_forwarding() {
    echo "------------------------------------------"
    echo "▶️  [功能：高级端口转发配置]"
    
    read -p "请输入本台服务器要【监听并暴露】的本地端口: " local_port
    if [ -z "$local_port" ]; then echo "❌ 错误: 本地端口不能为空"; return; fi

    choose_proto
    choose_ip_version
    enable_ip_forwarding  

    echo "----------------------------------"
    echo "👉 请选择转发的目的地类型："
    echo "1) 本机内部转发 (将流量转到本机的另一个端口，如 80 -> 8080)"
    echo "2) 外部服务器转发 (将流量跨网络转到另一台机器的特定 IP 和端口)"
    read -p "请选择 (1-2): " fwd_type

    if [ "$fwd_type" = "1" ]; then
        read -p "请输入本机的目标端口: " target_port
        target_ip="127.0.0.1"
        target_ip_v6="::1"
    else
        read -p "请输入远端目标服务器的 IP 地址 (IPv4 或 IPv6): " target_ip
        read -p "请输入远端目标服务器的端口号: " target_port
        if [ -z "$target_ip" ] || [ -z "$target_port" ]; then
            echo "❌ 错误: 目标 IP 或端口不能为空！"
            return
        fi
    fi

    local protos=("$PROTO")
    [ "$PROTO" = "both" ] && protos=("tcp" "udp")

    if [ "$CURRENT_FW" = "ufw" ]; then
        echo "💡 正在通过内置高可靠性 iptables/ip6tables 引擎构建 UFW 环境下的转发链..."
        for p in "${protos[@]}"; do
            if [ "$IP_VER" = "4" ] || [ "$IP_VER" = "both" ]; then
                iptables -t nat -A PREROUTING -p $p --dport $local_port -j DNAT --to-destination ${target_ip}:${target_port}
                iptables -t nat -A POSTROUTING -p $p -d $target_ip --dport $target_port -j MASQUERADE
                iptables -A FORWARD -p $p -d $target_ip --dport $target_port -j ACCEPT
            fi
            if [ "$IP_VER" = "6" ] || [ "$IP_VER" = "both" ]; then
                local t_ip6=$target_ip
                [ "$fwd_type" = "1" ] && t_ip6=$target_ip_v6
                
                ip6tables -t nat -A PREROUTING -p $p --dport $local_port -j DNAT --to-destination [${t_ip6}]:${target_port} >/dev/null 2>&1
                ip6tables -t nat -A POSTROUTING -p $p -d ${t_ip6} --dport $target_port -j MASQUERADE >/dev/null 2>&1
                ip6tables -A FORWARD -p $p -d ${t_ip6} --dport $target_port -j ACCEPT >/dev/null 2>&1
            fi
        done
        
        if command -v iptables-save >/dev/null 2>&1; then
            mkdir -p /etc/iptables/
            iptables-save > /etc/iptables/rules.v4
            ip6tables-save > /etc/iptables/rules.v6 2>/dev/null
        fi

    elif [ "$CURRENT_FW" = "firewalld" ]; then
        local zone=$(firewall-cmd --get-default-zone)
        firewall-cmd --permanent --zone="$zone" --add-masquerade
        
        for p in "${protos[@]}"; do
            if [ "$fwd_type" = "1" ]; then
                if [ "$IP_VER" = "4" ] || [ "$IP_VER" = "both" ]; then
                    firewall-cmd --permanent --zone="$zone" --add-forward-port=port=$local_port:proto=$p:toport=$target_port
                fi
                if [ "$IP_VER" = "6" ] || [ "$IP_VER" = "both" ]; then
                    firewall-cmd --permanent --zone="$zone" --add-rich-rule="rule family='ipv6' forward-port port='$local_port' protocol='$p' to-port='$target_port'" 2>/dev/null
                fi
            else
                if [ "$IP_VER" = "4" ] || [ "$IP_VER" = "both" ]; then
                    firewall-cmd --permanent --zone="$zone" --add-forward-port=port=$local_port:proto=$p:toport=$target_port:toaddr=$target_ip
                fi
                if [ "$IP_VER" = "6" ] || [ "$IP_VER" = "both" ]; then
                    firewall-cmd --permanent --zone="$zone" --add-rich-rule="rule family='ipv6' forward-port port='$local_port' protocol='$p' to-port='$target_port' to-addr='$target_ip'" 2>/dev/null
                fi
            fi
        done
        firewall-cmd --reload >/dev/null
    fi
    echo "✅ 端口转发策略部署成功！监听本地端口: [$local_port] -> 转发至: [${target_ip}:${target_port}]"
}

# ==========================================
# 8. 全景状态查看
# ==========================================
show_status() {
    echo "------------------------------------------------------------------"
    echo "📊 [当前系统核心防火墙规则及转发全景一览]"
    echo "------------------------------------------------------------------"
    if [ "$CURRENT_FW" = "ufw" ]; then
        ufw status verbose
        echo "🔗 --- 额外附加的内核 NAT 转发链表 (IPv4) ---"
        iptables -t nat -L PREROUTING -n --line-numbers 2>/dev/null
        echo "🔗 --- 额外附加的内核 NAT 转发链表 (IPv6) ---"
        ip6tables -t nat -L PREROUTING -n --line-numbers 2>/dev/null
    elif [ "$CURRENT_FW" = "firewalld" ]; then
        firewall-cmd --list-all
    fi
}

# ==========================================
# 9. 脚本主控制循环菜单
# ==========================================
main_menu() {
    while true; do
        echo ""
        echo "=================================================================="
        echo "   🛡️  Linux 智能多发行版自动化防火墙管理系统"
        echo "   当前环境发行版: ${OS_NAME^^} | 正在纳管的防火墙后端: ${CURRENT_FW^^}"
        echo "=================================================================="
        echo " 1) ⚡ 开启 / 关闭指定网络端口"
        echo " 2) 🔄 配置 内部 / 外部 端口转发 (支持 IPv4/IPv6 双栈)"
        echo " 3) 📊 实时查看当前全量防火墙规则和转发链"
        echo " 4) 🚨 重新执行 SSH 安全初始化 (如变更了端口或防锁死救援)"
        echo " 5) ❌ 安全退出脚本"
        echo "=================================================================="
        read -p "请选择您要执行的高级运维操作 (1-5): " menu_choice
        
        case $menu_choice in
            1) manage_ports ;;
            2) manage_forwarding ;;
            3) show_status ;;
            4) init_ssh_security ;;
            5) echo "👋 感谢使用！防火墙已安全托管运行，再见！"; exit 0 ;;
            *) echo "❌ 输入错误: 未知指令，请重新在 1 到 5 之间进行选择。" ;;
        esac
    done
}

# ==========================================
# 🚀 脚本执行总入口
# ==========================================
clear
detect_os
check_installed_firewalls
manage_installation

# 智能兜底
if [ -z "$CURRENT_FW" ]; then
    command -v ufw >/dev/null 2>&1 && CURRENT_FW="ufw"
    command -v firewall-cmd >/dev/null 2>&1 && CURRENT_FW="firewalld"
fi

if [ -z "$CURRENT_FW" ]; then
    echo "❌ 错误: 未检测到任何可用的防火墙后端（UFW 或 Firewalld），请重新运行脚本并选择进行安装！"
    exit 1
fi

# 强力触发 SSH 保护策略初始化
init_ssh_security

# 激活主操作循环
main_menu
