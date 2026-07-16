#!/bin/bash

# ==============================================================================
# 脚本名称: ssh-f.sh
# 版本号:   1.0.0
# 描述:     SSH + Fail2ban 交互式一键加固脚本
#           配合 sshs.sh 使用，提供企业级防护能力
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# 颜色定义
# ------------------------------------------------------------------------------
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ------------------------------------------------------------------------------
# 工具函数
# ------------------------------------------------------------------------------
print_header() {
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================================${NC}"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

# 确保以 root 权限运行
if [ "${EUID}" -ne 0 ]; then
    print_error "请使用 root 权限运行此脚本（例如: sudo ./ssh-failban-hardening.sh）"
    exit 1
fi

print_header "SSH + Fail2ban 交互式安全加固脚本 v1.0.0"

# ------------------------------------------------------------------------------
# 1. 检测当前 SSH 端口
# ------------------------------------------------------------------------------
echo ""
print_info "正在检测当前 SSH 配置..."

CURRENT_SSH_PORT=$(grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
print_info "检测到当前 SSH 端口: ${CURRENT_SSH_PORT}"

read -p "$(echo -e ${YELLOW}"[?]${NC} 确认使用端口 ${CURRENT_SSH_PORT} 进行加固? [Y/n]: ")" CONFIRM_PORT
CONFIRM_PORT=${CONFIRM_PORT:-Y}
CONFIRM_PORT=$(echo "${CONFIRM_PORT}" | tr '[:upper:]' '[:lower:]')

if [[ "${CONFIRM_PORT}" != "y" && "${CONFIRM_PORT}" != "yes" ]]; then
    print_error "已取消加固操作"
    exit 1
fi

SSH_PORT="${CURRENT_SSH_PORT}"

# ------------------------------------------------------------------------------
# 2. 选择防护等级
# ------------------------------------------------------------------------------
echo ""
print_header "选择防护等级"
echo "  1) 基础防护 - 适合个人 VPS（低流量）"
echo "     • 3 次失败封禁 1 小时"
echo "     • 基础日志记录"
echo ""
echo "  2) 标准防护 - 适合小型企业（中流量）"
echo "     • 2 次失败封禁 24 小时（递增至 30 天）"
echo "     • 连接速率限制"
echo "     • 邮件通知"
echo ""
echo "  3) 严格防护 - 适合高安全需求（敏感数据）"
echo "     • 1 次失败封禁 7 天"
echo "     • 激进的速率限制"
echo "     • 永久封禁累犯"
echo "     • 详细审计日志"
echo ""
read -p "$(echo -e ${YELLOW}"[?]${NC} 请选择防护等级 [1-3] (默认 2): ")" PROTECTION_LEVEL
PROTECTION_LEVEL=${PROTECTION_LEVEL:-2}

case ${PROTECTION_LEVEL} in
    1)
        MAXRETRY=3
        BANTIME=3600
        FINDTIME=600
        BANTIME_INCREMENT="false"
        RATE_LIMIT="false"
        EMAIL_NOTIFY="false"
        PERMANENT_BAN="false"
        print_success "已选择: 基础防护"
        ;;
    2)
        MAXRETRY=2
        BANTIME=86400
        FINDTIME=3600
        BANTIME_INCREMENT="true"
        RATE_LIMIT="true"
        EMAIL_NOTIFY="true"
        PERMANENT_BAN="false"
        print_success "已选择: 标准防护（推荐）"
        ;;
    3)
        MAXRETRY=1
        BANTIME=604800
        FINDTIME=3600
        BANTIME_INCREMENT="true"
        RATE_LIMIT="true"
        EMAIL_NOTIFY="true"
        PERMANENT_BAN="true"
        print_success "已选择: 严格防护"
        ;;
    *)
        print_error "无效的选择，已取消"
        exit 1
        ;;
esac

# ------------------------------------------------------------------------------
# 3. 邮件通知配置（如果需要）
# ------------------------------------------------------------------------------
EMAIL_ADDRESS=""
if [ "${EMAIL_NOTIFY}" = "true" ]; then
    echo ""
    print_info "邮件通知功能需要配置 SMTP 服务"
    read -p "$(echo -e ${YELLOW}"[?]${NC} 是否配置邮件通知? [y/N]: ")" SETUP_EMAIL
    SETUP_EMAIL=${SETUP_EMAIL:-N}
    SETUP_EMAIL=$(echo "${SETUP_EMAIL}" | tr '[:upper:]' '[:lower:]')
  
    if [[ "${SETUP_EMAIL}" == "y" || "${SETUP_EMAIL}" == "yes" ]]; then
        read -p "$(echo -e ${YELLOW}"[?]${NC} 请输入接收通知的邮箱地址: ")" EMAIL_ADDRESS
        if [[ ! "${EMAIL_ADDRESS}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            print_warning "邮箱格式无效，将跳过邮件通知配置"
            EMAIL_NOTIFY="false"
        fi
    else
        EMAIL_NOTIFY="false"
    fi
fi

# ------------------------------------------------------------------------------
# 4. SSH 配置优化选项
# ------------------------------------------------------------------------------
echo ""
print_header "SSH 配置优化"
echo "推荐启用以下安全增强选项："
echo "  • 限制认证尝试次数 (MaxAuthTries)"
echo "  • 限制并发连接数 (MaxStartups)"
echo "  • 禁用不需要的功能 (X11/TCP/Agent 转发)"
echo ""
read -p "$(echo -e ${YELLOW}"[?]${NC} 是否应用 SSH 配置优化? [Y/n]: ")" OPTIMIZE_SSH
OPTIMIZE_SSH=${OPTIMIZE_SSH:-Y}
OPTIMIZE_SSH=$(echo "${OPTIMIZE_SSH}" | tr '[:upper:]' '[:lower:]')

# ------------------------------------------------------------------------------
# 5. 确认配置摘要
# ------------------------------------------------------------------------------
echo ""
print_header "配置摘要"
echo "SSH 端口: ${SSH_PORT}"
echo "防护等级: $([ ${PROTECTION_LEVEL} -eq 1 ] && echo '基础' || [ ${PROTECTION_LEVEL} -eq 2 ] && echo '标准' || echo '严格')"
echo "失败次数: ${MAXRETRY} 次"
echo "封禁时长: $((BANTIME / 3600)) 小时"
echo "递增封禁: $([ "${BANTIME_INCREMENT}" = "true" ] && echo '启用（最长 30 天）' || echo '禁用')"
echo "速率限制: $([ "${RATE_LIMIT}" = "true" ] && echo '启用' || echo '禁用')"
echo "邮件通知: $([ "${EMAIL_NOTIFY}" = "true" ] && echo "启用 (${EMAIL_ADDRESS})" || echo '禁用')"
echo "永久封禁: $([ "${PERMANENT_BAN}" = "true" ] && echo '启用' || echo '禁用')"
echo "SSH 优化: $([ "${OPTIMIZE_SSH}" = "y" ] || [ "${OPTIMIZE_SSH}" = "yes" ] && echo '启用' || echo '禁用')"
echo ""
read -p "$(echo -e ${YELLOW}"[?]${NC} 确认开始加固? [Y/n]: ")" CONFIRM_START
CONFIRM_START=${CONFIRM_START:-Y}
CONFIRM_START=$(echo "${CONFIRM_START}" | tr '[:upper:]' '[:lower:]')

if [[ "${CONFIRM_START}" != "y" && "${CONFIRM_START}" != "yes" ]]; then
    print_error "已取消加固操作"
    exit 1
fi

# ------------------------------------------------------------------------------
# 6. 开始安装和配置
# ------------------------------------------------------------------------------
echo ""
print_header "开始系统加固"

# 6.1 安装必要组件
print_info "正在安装必要组件..."
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y >/dev/null 2>&1
    apt-get install -y fail2ban iptables-persistent >/dev/null 2>&1
    if [ "${EMAIL_NOTIFY}" = "true" ]; then
        apt-get install -y mailutils >/dev/null 2>&1 || print_warning "mailutils 安装失败，邮件通知将不可用"
    fi
elif command -v yum >/dev/null 2>&1; then
    yum install -y epel-release >/dev/null 2>&1
    yum install -y fail2ban iptables-services >/dev/null 2>&1
    if [ "${EMAIL_NOTIFY}" = "true" ]; then
        yum install -y mailx >/dev/null 2>&1 || print_warning "mailx 安装失败，邮件通知将不可用"
    fi
else
    print_error "不支持的系统，仅支持 Debian/Ubuntu/CentOS/RHEL"
    exit 1
fi
print_success "组件安装完成"

# 6.2 备份现有配置
print_info "正在备份现有配置..."
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
if [ -f /etc/fail2ban/jail.local ]; then
    cp /etc/fail2ban/jail.local /etc/fail2ban/jail.local.bak.${BACKUP_TIMESTAMP}
    print_success "已备份 jail.local"
fi
print_success "配置备份完成"

# 6.3 配置 Fail2ban
print_info "正在配置 Fail2ban..."

cat > /etc/fail2ban/jail.local << EOF
# ==============================================================================
# Fail2ban 配置 - 由 ssh-failban-hardening.sh 自动生成
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# 防护等级: $([ ${PROTECTION_LEVEL} -eq 1 ] && echo '基础' || [ ${PROTECTION_LEVEL} -eq 2 ] && echo '标准' || echo '严格')
# ==============================================================================

[DEFAULT]
# 基础封禁配置
bantime = ${BANTIME}
findtime = ${FINDTIME}
maxretry = ${MAXRETRY}

# 递增封禁配置
bantime.increment = ${BANTIME_INCREMENT}
EOF

if [ "${BANTIME_INCREMENT}" = "true" ]; then
    cat >> /etc/fail2ban/jail.local << EOF
bantime.factor = 2
bantime.maxtime = 2592000  # 最长 30 天
EOF
fi

if [ "${EMAIL_NOTIFY}" = "true" ] && [ -n "${EMAIL_ADDRESS}" ]; then
    cat >> /etc/fail2ban/jail.local << EOF

# 邮件通知配置
destemail = ${EMAIL_ADDRESS}
sender = fail2ban@$(hostname)
action = %(action_mwl)s
EOF
fi

cat >> /etc/fail2ban/jail.local << EOF

# SSH 防护配置
[sshd]
enabled = true
port = ${SSH_PORT}
filter = sshd
logpath = /var/log/auth.log
maxretry = ${MAXRETRY}
EOF

if [ "${PERMANENT_BAN}" = "true" ]; then
    cat >> /etc/fail2ban/jail.local << EOF
banaction = iptables-allports
EOF
else
    cat >> /etc/fail2ban/jail.local << EOF
banaction = iptables-multiport
EOF
fi

print_success "Fail2ban 配置完成"

# 6.4 配置连接速率限制（如果启用）
if [ "${RATE_LIMIT}" = "true" ]; then
    print_info "正在配置连接速率限制..."
  
    # 检查规则是否已存在
    if ! iptables -C INPUT -p tcp --dport ${SSH_PORT} -m state --state NEW -m recent --set --name SSH 2>/dev/null; then
        iptables -I INPUT -p tcp --dport ${SSH_PORT} -m state --state NEW -m recent --set --name SSH
    fi
  
    if [ "${PROTECTION_LEVEL}" -eq 3 ]; then
        # 严格模式: 60 秒最多 2 次连接
        if ! iptables -C INPUT -p tcp --dport ${SSH_PORT} -m state --state NEW -m recent --update --seconds 60 --hitcount 3 --rttl --name SSH -j DROP 2>/dev/null; then
            iptables -I INPUT -p tcp --dport ${SSH_PORT} -m state --state NEW -m recent --update --seconds 60 --hitcount 3 --rttl --name SSH -j DROP
        fi
        print_success "速率限制: 60 秒最多 2 次连接"
    else
        # 标准模式: 60 秒最多 4 次连接
        if ! iptables -C INPUT -p tcp --dport ${SSH_PORT} -m state --state NEW -m recent --update --seconds 60 --hitcount 5 --rttl --name SSH -j DROP 2>/dev/null; then
            iptables -I INPUT -p tcp --dport ${SSH_PORT} -m state --state NEW -m recent --update --seconds 60 --hitcount 5 --rttl --name SSH -j DROP
        fi
        print_success "速率限制: 60 秒最多 4 次连接"
    fi
  
    # 持久化 iptables 规则
    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save >/dev/null 2>&1
    elif [ -d /etc/iptables ]; then
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    elif [ -d /etc/sysconfig ]; then
        iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
    fi
    print_success "iptables 规则已持久化"
fi

# 6.5 SSH 配置优化（如果启用）
if [[ "${OPTIMIZE_SSH}" == "y" || "${OPTIMIZE_SSH}" == "yes" ]]; then
    print_info "正在优化 SSH 配置..."
  
    # 备份 sshd_config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.${BACKUP_TIMESTAMP}
  
    # 清理可能存在的重复配置
    sed -i '/^MaxAuthTries/d' /etc/ssh/sshd_config
    sed -i '/^MaxStartups/d' /etc/ssh/sshd_config
    sed -i '/^MaxSessions/d' /etc/ssh/sshd_config
    sed -i '/^ClientAliveInterval/d' /etc/ssh/sshd_config
    sed -i '/^ClientAliveCountMax/d' /etc/ssh/sshd_config
    sed -i '/^X11Forwarding/d' /etc/ssh/sshd_config
    sed -i '/^AllowTcpForwarding/d' /etc/ssh/sshd_config
    sed -i '/^AllowAgentForwarding/d' /etc/ssh/sshd_config
  
    # 添加优化配置
    cat >> /etc/ssh/sshd_config << EOF

# ==============================================================================
# SSH 安全优化 - 由 ssh-failban-hardening.sh 自动生成
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# ==============================================================================

# 限制认证尝试次数
MaxAuthTries 2

# 限制并发未认证连接
MaxStartups 3:50:10

# 限制单个用户的最大会话数
MaxSessions 3

# 客户端存活检测（5 分钟无响应断开）
ClientAliveInterval 300
ClientAliveCountMax 2

# 禁用不必要的功能
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
EOF
  
    # 验证配置语法
    if sshd -t 2>/dev/null; then
        print_success "SSH 配置优化完成"
    else
        print_error "SSH 配置语法错误，正在恢复备份..."
        cp /etc/ssh/sshd_config.bak.${BACKUP_TIMESTAMP} /etc/ssh/sshd_config
        print_warning "SSH 配置优化失败，已恢复原配置"
    fi
fi

# 6.6 启动服务
print_info "正在启动服务..."

# 启动 Fail2ban
systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban

# 重启 SSH（如果配置被修改）
if [[ "${OPTIMIZE_SSH}" == "y" || "${OPTIMIZE_SSH}" == "yes" ]]; then
    # 检测 SSH 服务名
    if systemctl list-units --type=service 2>/dev/null | grep -q "sshd.service"; then
        SSH_SERVICE_NAME="sshd"
    else
        SSH_SERVICE_NAME="ssh"
    fi
    systemctl restart ${SSH_SERVICE_NAME}
    print_success "SSH 服务已重启"
fi

print_success "所有服务已启动"

# ------------------------------------------------------------------------------
# 7. 验证配置
# ------------------------------------------------------------------------------
echo ""
print_header "配置验证"

# 检查 Fail2ban 状态
if systemctl is-active --quiet fail2ban; then
    print_success "Fail2ban 服务运行正常"
  
    # 检查 sshd jail 状态
    if fail2ban-client status sshd >/dev/null 2>&1; then
        print_success "SSH 防护已激活"
      
        # 显示当前统计
        CURRENT_BANNED=$(fail2ban-client status sshd | grep "Currently banned" | awk '{print $NF}')
        TOTAL_BANNED=$(fail2ban-client status sshd | grep "Total banned" | awk '{print $NF}')
        print_info "当前封禁 IP 数: ${CURRENT_BANNED}"
        print_info "累计封禁次数: ${TOTAL_BANNED}"
    else
        print_warning "SSH 防护 jail 未找到"
    fi
else
    print_error "Fail2ban 服务未运行"
fi

# 检查 iptables 规则
if [ "${RATE_LIMIT}" = "true" ]; then
    if iptables -L INPUT -n | grep -q "${SSH_PORT}"; then
        print_success "连接速率限制已生效"
    else
        print_warning "连接速率限制可能未生效"
    fi
fi

# ------------------------------------------------------------------------------
# 8. 生成使用说明
# ------------------------------------------------------------------------------
echo ""
print_header "加固完成！"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  防护配置摘要"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SSH 端口:       ${SSH_PORT}"
echo "失败阈值:       ${MAXRETRY} 次"
echo "封禁时长:       $((BANTIME / 3600)) 小时"
if [ "${BANTIME_INCREMENT}" = "true" ]; then
    echo "递增封禁:       启用（重复违规最长封禁 30 天）"
fi
if [ "${RATE_LIMIT}" = "true" ]; then
    if [ "${PROTECTION_LEVEL}" -eq 3 ]; then
        echo "速率限制:       60 秒最多 2 次连接"
    else
        echo "速率限制:       60 秒最多 4 次连接"
    fi
fi
if [ "${EMAIL_NOTIFY}" = "true" ] && [ -n "${EMAIL_ADDRESS}" ]; then
    echo "邮件通知:       ${EMAIL_ADDRESS}"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "常用管理命令:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "# 查看 SSH 防护状态"
echo "  fail2ban-client status sshd"
echo ""
echo "# 查看当前封禁的 IP 列表"
echo "  fail2ban-client get sshd banip"
echo ""
echo "# 手动封禁 IP"
echo "  fail2ban-client set sshd banip <IP地址>"
echo ""
echo "# 解封 IP"
echo "  fail2ban-client set sshd unbanip <IP地址>"
echo ""
echo "# 查看实时日志"
echo "  tail -f /var/log/fail2ban.log"
echo ""
echo "# 查看 iptables 规则"
echo "  iptables -L INPUT -n -v | grep ${SSH_PORT}"
echo ""
echo "# 重启 Fail2ban"
echo "  systemctl restart fail2ban"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

print_warning "重要提示:"
echo "  1. 请确保你当前的 IP 不会被误封（测试前先加入白名单）"
echo "  2. 配置文件位置: /etc/fail2ban/jail.local"
echo "  3. 备份文件已保存到: /etc/fail2ban/jail.local.bak.${BACKUP_TIMESTAMP}"
if [[ "${OPTIMIZE_SSH}" == "y" || "${OPTIMIZE_SSH}" == "yes" ]]; then
    echo "  4. SSH 配置备份: /etc/ssh/sshd_config.bak.${BACKUP_TIMESTAMP}"
fi
echo ""

# 添加当前 IP 到白名单提示
CURRENT_IP=$(who am i | awk '{print $NF}' | tr -d '()')
if [ -n "${CURRENT_IP}" ] && [ "${CURRENT_IP}" != "(:0)" ]; then
    echo "检测到你的当前 IP: ${CURRENT_IP}"
    read -p "$(echo -e ${YELLOW}"[?]${NC} 是否将此 IP 加入 Fail2ban 白名单? [Y/n]: ")" ADD_WHITELIST
    ADD_WHITELIST=${ADD_WHITELIST:-Y}
    ADD_WHITELIST=$(echo "${ADD_WHITELIST}" | tr '[:upper:]' '[:lower:]')
  
    if [[ "${ADD_WHITELIST}" == "y" || "${ADD_WHITELIST}" == "yes" ]]; then
        sed -i "/^\[DEFAULT\]/a ignoreip = 127.0.0.1/8 ::1 ${CURRENT_IP}" /etc/fail2ban/jail.local
        systemctl restart fail2ban
        print_success "IP ${CURRENT_IP} 已加入白名单"
    fi
fi

echo ""
print_success "系统加固完成！建议重启服务器以确保所有配置生效。"
echo ""
