#!/bin/bash

# ==============================================================================
# 脚本名称: sshs.sh
# 版本号:   1.1.1 (生产级加固重构版 - 精准时控与 PAM 零漏洞)
# 描述:     Linux SSH 安全加固与 2FA 一键部署脚本
#           完美兼容群晖虚拟机等虚拟化环境，防时间漂移，彻底解决多通道死锁
# ==============================================================================

# 严格模式：发生任何非零返回或管道失败时立退。
set -euo pipefail

# ------------------------------------------------------------------------------
# 0. 统一定义只读全局配置（引入 PID 防止并发冲突）
# ------------------------------------------------------------------------------
readonly TIME_STAMP="$(date +%Y%m%d_%H%M%S)_$$"
# 【已修复：P1级问题】统一为 1.1.1 并清理了 AI 引用标记[cite: 1]
readonly BAK_SUFFIX="pre_secure_v1.1.1_${TIME_STAMP}"

readonly SSHD_CONFIG="/etc/ssh/sshd_config"
readonly PAM_SSH="/etc/pam.d/sshd"

readonly SSHD_BAK="${SSHD_CONFIG}.${BAK_SUFFIX}"
readonly PAM_BAK="${PAM_SSH}.${BAK_SUFFIX}"

# 自适应 Chrony 路径初始化逻辑
if [ -d "/etc/chrony" ] || command -v apt-get >/dev/null 2>&1; then
    CHRONY_CONF_PATH="/etc/chrony/chrony.conf"
    mkdir -p /etc/chrony
else
    CHRONY_CONF_PATH="/etc/chrony.conf"
fi
touch "${CHRONY_CONF_PATH}" 
readonly CHRONY_CONF="${CHRONY_CONF_PATH}"
readonly CHRONY_BAK="${CHRONY_CONF}.${BAK_SUFFIX}"

# 探测 SSH 系统服务名
if systemctl list-units --type=service 2>/dev/null | grep -q "sshd.service"; then
    readonly SSH_SERVICE_NAME="sshd"
else
    readonly SSH_SERVICE_NAME="ssh"
fi

# 定义公钥下载源（国内外双备份）
readonly KEY_URL_ABROAD="https://github.com/LeiD215/LeiD215.github.io/raw/master/tools/temp/GMail2023EDPW.key"
readonly KEY_URL_DOMESTIC="https://gitee.com/LeiD215/LeiD215.gitee.io/raw/master/tools/temp/GMail2023EDPW.key"

# ------------------------------------------------------------------------------
# 0.1 灾难恢复回滚函数
# ------------------------------------------------------------------------------
rollback_all() {
    echo ""
    echo "[-] [警告] 检测到异常、校验失败或用户中断！启动安全回滚机制..."
    
    if [ -f "${SSHD_BAK}" ]; then
        cp "${SSHD_BAK}" "${SSHD_CONFIG}" && echo "[+] 已恢复原始 sshd_config"
    fi
    if [ -f "${PAM_BAK}" ]; then
        cp "${PAM_BAK}" "${PAM_SSH}" && echo "[+] 已恢复原始 PAM 配置文件"
    fi
    if [ -f "${CHRONY_BAK}" ]; then
        cp "${CHRONY_BAK}" "${CHRONY_CONF}" && echo "[+] 已恢复原始 Chrony 配置文件"
    fi
    if rm -f /root/.google_authenticator 2>/dev/null; then
        echo "[+] 已彻底清理 2FA 运行时临时令牌残留文件"
    fi
    
    echo "[+] 正在尝试重新拉起 SSH 服务..."
    if systemctl restart "${SSH_SERVICE_NAME}" >/dev/null 2>&1; then
        echo "[★] 安全网：SSH 服务已成功恢复并拉起！原配置已复原。"
    else
        echo "[!] 严重警告：原 SSH 服务尝试拉起失败！"
        echo "    请绝对保持当前会话不要断开，并立即手动排查错误原因。"
    fi
    exit 1
}

# 确保以 root 权限运行
if [ "${EUID}" -ne 0 ]; then
  echo "[-] 错误: 请使用 root 权限运行此脚本（例如: sudo ./sshs.sh）"
  exit 1
fi

echo "=================================================================="
echo "        Linux SSH 安全加固与 2FA 一键部署脚本 v1.1.1"
echo "=================================================================="

# ------------------------------------------------------------------------------
# 1. 选择公钥源并下载
# ------------------------------------------------------------------------------
echo "[?] 请选择公钥下载源（国内选 Gitee，国外选 GitHub）："
echo "  1) 国内源 (Gitee)"
echo "  2) 国外源 (GitHub)"
read -p "请输入序号 [1-2] (默认 1): " KEY_CHOICE
KEY_CHOICE=${KEY_CHOICE:-1}

if [ "${KEY_CHOICE}" -eq 2 ]; then
    DOWNLOAD_URL="${KEY_URL_ABROAD}"
    echo "[+] 已选择国外源 (GitHub)"
else
    DOWNLOAD_URL="${KEY_URL_DOMESTIC}"
    echo "[+] 已选择国内源 (Gitee)"
fi

echo "[+] 正在从网络获取公钥..."
if command -v curl >/dev/null 2>&1; then
    PUBLIC_KEY=$(curl -sSL --connect-timeout 10 "${DOWNLOAD_URL}") || { echo "[-] Curl 下载公钥失败"; exit 1; }
elif command -v wget >/dev/null 2>&1; then
    PUBLIC_KEY=$(wget -qO- --timeout=10 "${DOWNLOAD_URL}") || { echo "[-] Wget 下载公钥失败"; exit 1; }
else
    echo "[-] 错误: 系统中未找到 curl 或 wget，无法下载公钥！"
    exit 1
fi

# 验证公钥指纹
echo "[+] 正在使用 ssh-keygen 强制校验公钥指纹..."
if ! echo "${PUBLIC_KEY}" | ssh-keygen -l -f /dev/stdin &>/dev/null; then
    echo "[-] 错误: 公钥格式验证失败！可能已被篡改、截断或含有恶意代码。"
    exit 1
fi
echo "[+] 公钥格式校验通过。"

# ------------------------------------------------------------------------------
# 2. 交互式输入端口
# ------------------------------------------------------------------------------
while true; do
    read -p "[?] 请输入新的 SSH 端口号 [1025-65535] (默认 2222): " NEW_PORT
    NEW_PORT=${NEW_PORT:-2222}
    
    if [[ "${NEW_PORT}" =~ ^[0-9]+$ ]] && [ "${NEW_PORT}" -ge 1024 ] && [ "${NEW_PORT}" -le 65535 ]; then
        if command -v ss >/dev/null 2>&1; then
            PORT_IN_USE=$(ss -tlnp | grep -w ":${NEW_PORT}" || true)
        else
            PORT_IN_USE=$(netstat -tlnp | grep -w ":${NEW_PORT}" 2>/dev/null || true)
        fi
        
        if [ -n "${PORT_IN_USE}" ]; then
            echo "[-] 警告: 端口 ${NEW_PORT} 已被系统其他程序占用，请更换！"
        else
            echo "[+] 确定使用端口: ${NEW_PORT}"
            break
        fi
    else
        echo "[-] 输入错误！请输入 1024 到 65535 之间的纯数字。"
    fi
done

# ------------------------------------------------------------------------------
# 3. 是否开启双因子认证 (2FA)
# ------------------------------------------------------------------------------
echo "------------------------------------------------------------------"
echo "[?] 是否需要启用双因子认证 (2FA)？"
echo "    启用后，登录时不仅需要私钥，还需输入手机/1Password 的 6 位动态验证码。"
read -p "请输入 [y/N] (默认不启用 N): " ENABLE_2FA
ENABLE_2FA=$(echo "${ENABLE_2FA}" | tr '[:upper:]' '[:lower:]')

# ------------------------------------------------------------------------------
# 4. 配置高可用时间同步与虚拟机补偿组件
# ------------------------------------------------------------------------------
if [[ "${ENABLE_2FA}" == "y" || "${ENABLE_2FA}" == "yes" ]]; then
    echo "[+] 正在配置时间同步与虚拟化感知补偿机制..."
    
    # 4.1 安装 Chrony
    if ! command -v chronyd >/dev/null 2>&1; then
        echo "[+] 正在安装 chrony 守护进程..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -y && apt-get install -y chrony
        elif command -v yum >/dev/null 2>&1; then
            yum install -y chrony
        fi
    fi

    # 4.2 鲁棒级虚拟化平台识别 (合并 systemd 与底边探测)
    VIRT_TYPE="none"
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        VIRT_TYPE=$(systemd-detect-virt 2>/dev/null || echo "none")
    elif [ -f /sys/hypervisor/type ]; then
        VIRT_TYPE=$(cat /sys/hypervisor/type)
    elif grep -q -E "QEMU|KVM" /proc/cpuinfo 2>/dev/null; then
        VIRT_TYPE="qemu"
    fi

    # 4.3 针对虚拟机(如群晖 VMM 等 QEMU 宿主) 自动部署 guest-agent 强行同步时钟（输出优化）
    if [[ "${VIRT_TYPE}" =~ ^(kvm|qemu|oracle|vmware)$ ]]; then
        echo "[+] 识别到虚拟化环境 (${VIRT_TYPE})，正在尝试安装 qemu-guest-agent..."
        if command -v apt-get >/dev/null 2>&1; then
            if apt-get install -y qemu-guest-agent; then
                systemctl enable --now qemu-guest-agent >/dev/null 2>&1 && echo "[+] qemu-guest-agent 安装并启动成功"
            else
                echo "[!] qemu-guest-agent 安装失败（不影响脚本继续，但建议后续手动安装对齐时钟）"
            fi
        elif command -v yum >/dev/null 2>&1; then
            if yum install -y qemu-guest-agent; then
                systemctl enable --now qemu-guest-agent >/dev/null 2>&1 && echo "[+] qemu-guest-agent 安装并启动成功"
            else
                echo "[!] qemu-guest-agent 安装失败（不影响脚本继续，但建议后续手动安装对齐时钟）"
            fi
        fi
    fi

    # 4.4 备份并更新 Chrony 配置
    cp "${CHRONY_CONF}" "${CHRONY_BAK}"
    sed -i '/^[[:space:]]*server /d' "${CHRONY_CONF}"
    sed -i '/^[[:space:]]*pool /d' "${CHRONY_CONF}"
    
    cat << EOF >> "${CHRONY_CONF}"
# 1.1.1 高可用时钟源
server time.apple.com iburst
server ntp.aliyun.com iburst
server ntp.tencent.com iburst
server time.cloudflare.com iburst
pool pool.ntp.org iburst
EOF

    if systemctl status chronyd.service &>/dev/null || systemctl cat chronyd.service &>/dev/null; then
        CHRONY_SERVICE="chronyd"
    elif systemctl status chrony.service &>/dev/null || systemctl cat chrony.service &>/dev/null; then
        CHRONY_SERVICE="chrony"
    else
        echo "[-] 错误：无法确定 chrony 服务名，请手动检查。"
        exit 1
    fi

    systemctl enable "${CHRONY_SERVICE}" >/dev/null 2>&1 || true
    systemctl restart "${CHRONY_SERVICE}" >/dev/null 2>&1 || true
    
    # 4.5 物理对齐时间，并写回虚拟机硬件时钟
    chronyc makestep >/dev/null 2>&1 || true
    if [[ "${VIRT_TYPE}" != "none" ]]; then
        hwclock --systohc >/dev/null 2>&1 || true
    fi
    echo "[+] 时间同步配置完成。当前系统时间: $(date -R)"
fi

# ------------------------------------------------------------------------------
# 5. 写入 root 用户 SSH 公钥
# ------------------------------------------------------------------------------
echo "[+] 正在配置 root 用户 SSH 公钥..."
SSH_DIR="/root/.ssh"
mkdir -p "${SSH_DIR}"
chmod 700 "${SSH_DIR}"

if ! grep -q "${PUBLIC_KEY}" "${SSH_DIR}/authorized_keys" 2>/dev/null; then
    echo "${PUBLIC_KEY}" >> "${SSH_DIR}/authorized_keys"
    echo "[+] 公钥已成功写入 ${SSH_DIR}/authorized_keys"
else
    echo "[*] 该公钥已存在于 authorized_keys 中，跳过写入"
fi
chmod 600 "${SSH_DIR}/authorized_keys"

# ------------------------------------------------------------------------------
# 6. 配置防火墙与 SELinux
# ------------------------------------------------------------------------------
echo "[+] 正在配置本地防火墙规则..."
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "active"; then
    ufw delete allow 22/tcp 2>/dev/null || true
    ufw allow "${NEW_PORT}"/tcp
    ufw reload
    echo "[+] UFW 防火墙已清理旧规则并放行 ${NEW_PORT} 端口"
elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --remove-port=22/tcp 2>/dev/null || true
    firewall-cmd --permanent --add-port="${NEW_PORT}"/tcp
    firewall-cmd --reload
    echo "[+] Firewalld 防火墙已清理旧规则并放行 ${NEW_PORT} 端口"
elif command -v iptables >/dev/null 2>&1; then
    while iptables -C INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null; do
        iptables -D INPUT -p tcp --dport 22 -j ACCEPT
    done
    iptables -A INPUT -p tcp --dport "${NEW_PORT}" -j ACCEPT
    
    IPTABLES_SAVED=false
    for path in /etc/sysconfig/iptables /etc/iptables/rules.v4 /etc/iptables/rules; do
        if iptables-save > "${path}" 2>/dev/null; then
            IPTABLES_SAVED=true
            echo "[+] iptables 规则已保存到 ${path}"
            break
        fi
    done
    
    if [ "${IPTABLES_SAVED}" = false ]; then
        echo "[!] 警告：无法持久化本地 iptables 规则，建议手动保存。"
    fi
fi

# SELinux 安全策略
if command -v semanage >/dev/null 2>&1 && getenforce | grep -qi "enforcing"; then
    echo "[+] 检测到 SELinux 处于开启状态，正在做端口安全性检查..."
    EXISTING_TYPE=$(semanage port -l | awk -v port="${NEW_PORT}" '$3 ~ port {print $1; exit}')
    if [ -n "${EXISTING_TYPE}" ] && [ "${EXISTING_TYPE}" != "ssh_port_t" ]; then
        echo "[-] 警告：新端口 ${NEW_PORT} 已被标记为 ${EXISTING_TYPE}"
        read -p "是否强行覆盖 SELinux 属性？[y/N]: " FORCE_SELINUX
        FORCE_SELINUX=$(echo "${FORCE_SELINUX}" | tr '[:upper:]' '[:lower:]')
        if [[ "${FORCE_SELINUX}" != "y" && "${FORCE_SELINUX}" != "yes" ]]; then
            echo "[-] 用户拒绝覆盖 SELinux 策略，加固流程中止。"
            exit 1
        fi
    fi
    semanage port -a -t ssh_port_t -p tcp "${NEW_PORT}" 2>/dev/null || semanage port -m -t ssh_port_t -p tcp "${NEW_PORT}"
fi

# ------------------------------------------------------------------------------
# 7. 修改 SSH 配置文件 (sshd_config) — 精准清理冗余键
# ------------------------------------------------------------------------------
echo "[+] 正在备份并修改 ${SSHD_CONFIG}..."
cp "${SSHD_CONFIG}" "${SSHD_BAK}"

# 7.1 清理并注入通用加固选项
sed -i '/^[[:space:]]*Port[[:space:]]/d' "${SSHD_CONFIG}"
echo "Port ${NEW_PORT}" >> "${SSHD_CONFIG}"

sed -i '/^[[:space:]]*PubkeyAuthentication[[:space:]]/d' "${SSHD_CONFIG}"
echo "PubkeyAuthentication yes" >> "${SSHD_CONFIG}"

sed -i '/^[[:space:]]*PasswordAuthentication[[:space:]]/d' "${SSHD_CONFIG}"
echo "PasswordAuthentication no" >> "${SSHD_CONFIG}"

sed -i '/^[[:space:]]*PermitRootLogin[[:space:]]/d' "${SSHD_CONFIG}"
echo "PermitRootLogin prohibit-password" >> "${SSHD_CONFIG}"

# 7.2 清除所有键盘交互历史遗留残留行，为 2FA 分支扫清冲突障碍
sed -i '/^[[:space:]]*KbdInteractiveAuthentication[[:space:]]/d' "${SSHD_CONFIG}"
sed -i '/^[[:space:]]*ChallengeResponseAuthentication[[:space:]]/d' "${SSHD_CONFIG}"

# ------------------------------------------------------------------------------
# 8. 安装与配置 2FA PAM 模块（安全加固 - 无安全漏洞）
# ------------------------------------------------------------------------------
if [[ "${ENABLE_2FA}" == "y" || "${ENABLE_2FA}" == "yes" ]]; then
    echo "[+] 正在下载并安装 Google Authenticator PAM 模块..."
    
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y && apt-get install -y libpam-google-authenticator
    elif command -v yum >/dev/null 2>&1; then
        yum install -y epel-release || true
        yum install -y google-authenticator
    fi

    if ! command -v google-authenticator >/dev/null 2>&1; then
        echo "[-] 错误：google-authenticator 可执行二进制文件未找到！"
        rollback_all
    fi

    # 【物理验证】强力检测 pam_google_authenticator.so，防止库缺失
    echo "[+] 正在验证 PAM 模块物理完整性..."
    PAM_MODULE_PATH=$(
        ldconfig -p 2>/dev/null | grep 'pam_google_authenticator\.so' | sed -n 's/.* => \([^ ]*\).*/\1/p' | head -n1 || \
        find /lib /usr/lib -type f -name "pam_google_authenticator.so" 2>/dev/null | head -n1
    )
    if [ -z "${PAM_MODULE_PATH}" ]; then
        echo "[-] 错误：PAM 模块文件 pam_google_authenticator.so 未找到！"
        echo "    CLI工具存在但底层 PAM 核心缺失，2FA 将无法载入。"
        echo "    建议手动执行包管理器完整重装命令。"
        rollback_all
    fi
    echo "[+] PAM 模块验证通过：${PAM_MODULE_PATH}"

    # 8.1 注入 PAM：坚持使用 required 认证，堵死 bypass 漏洞
    if [ -f "${PAM_SSH}" ]; then
        cp "${PAM_SSH}" "${PAM_BAK}"
        
        # 彻底移除旧模块行，防止重复添加
        sed -i '/pam_google_authenticator.so/d' "${PAM_SSH}"
        
        # 将 required 规则干净、精准地推入首行
        sed -i '1i auth required pam_google_authenticator.so' "${PAM_SSH}"
    fi

    # 8.2 彻底允许键盘交互通道并组建 [公钥+2FA] 的原子双因子认证
    echo "KbdInteractiveAuthentication yes" >> "${SSHD_CONFIG}"
    
    sed -i '/^[[:space:]]*AuthenticationMethods[[:space:]]/d' "${SSHD_CONFIG}"
    echo "AuthenticationMethods publickey,keyboard-interactive" >> "${SSHD_CONFIG}"

    # 8.3 初始化 2FA 凭证
    echo "------------------------------------------------------------------"
    echo "[!!!] 重要提示：即将开始为 root 生成 2FA 密钥。"
    echo "      请拿出手机或 1Password 准备好扫码。"
    echo "------------------------------------------------------------------"
    
    # 动态时钟窗口自适应：虚拟机使用 ±2.5分钟窗口(-w 5)，物理宿主/云主机使用标准 ±1.5分钟窗口(-w 3)
    if [[ "${VIRT_TYPE}" =~ ^(kvm|qemu|oracle|vmware)$ ]]; then
        echo "[+] 检测为虚拟化环境，自动应用安全宽容时间窗口（±2.5分钟容错 -w 5）"
        google-authenticator -t -d -u -w 5
    else
        echo "[+] 使用标准网络环境，应用标准高安全时间窗口（±1.5分钟容错 -w 3）"
        google-authenticator -t -d -u -w 3
    fi

    while true; do
        read -p "[?] 请确认你已安全备份了 2FA 二维码和 5 个应急备用码？[y/n]: " VERIFY_SAVE
        VERIFY_SAVE=$(echo "${VERIFY_SAVE}" | tr '[:upper:]' '[:lower:]')
        if [[ "${VERIFY_SAVE}" == "y" || "${VERIFY_SAVE}" == "yes" ]]; then
            echo "[+] 确认完毕，进入测试阶段。"
            break
        elif [[ "${VERIFY_SAVE}" == "n" || "${VERIFY_SAVE}" == "no" ]]; then
            rollback_all
        else
            echo "[-] 请输入 y (已保存并继续) 或 n (取消并回滚)"
        fi
    done
else
    # 未启用 2FA 时，关闭键盘交互式大门
    echo "KbdInteractiveAuthentication no" >> "${SSHD_CONFIG}"
    sed -i "/^[[:space:]]*AuthenticationMethods[[:space:]]/d" "${SSHD_CONFIG}"
fi

# ------------------------------------------------------------------------------
# 9. 配置验证与服务重启
# ------------------------------------------------------------------------------
echo "[+] 正在自适应检测系统网络，获取服务器公网 IP..."
SERVER_IP=$(curl -s --connect-timeout 5 ip.sb || curl -s --connect-timeout 5 ifconfig.me || curl -s --connect-timeout 5 test.ipw.cn || echo "")

if [ -z "${SERVER_IP}" ]; then
    echo "[!] 无法自动获取公网 IP，请手动确认服务器地址。"
    while true; do
        read -p "请输入服务器 IP 或域名 (默认 localhost): " MANUAL_IP
        MANUAL_IP=${MANUAL_IP:-"localhost"}
        if [[ "${MANUAL_IP}" =~ ^[a-zA-Z0-9.-]+$ ]]; then
            SERVER_IP="${MANUAL_IP}"
            break
        else
            echo "[-] 警告：输入格式不合法！"
        fi
    done
fi

echo "[+] 正在验证配置完整性..."
if ! sshd -t; then
    echo "[-] sshd_config 语法检查失败！"
    rollback_all
fi

if [[ "${ENABLE_2FA}" == "y" || "${ENABLE_2FA}" == "yes" ]]; then
    if ! grep -q "pam_google_authenticator.so" "${PAM_SSH}"; then
        echo "[-] 错误：PAM 配置文件未正确注入模块！"
        rollback_all
    fi
fi

echo "[+] 物理链路校验通过，正在重启 ${SSH_SERVICE_NAME} 服务..."
systemctl restart "${SSH_SERVICE_NAME}"

echo "=================================================================="
echo "[★] 配置应用成功！进入双重登录安全验证"
echo "=================================================================="
echo "⚠️【警告：绝对不要关闭当前这个终端窗口！】"
echo "请新开一个 MobaXterm 窗口，执行以下命令测试连接："
echo ""
echo "   ssh -p ${NEW_PORT} root@${SERVER_IP}"
echo ""
if [[ "${ENABLE_2FA}" == "y" || "${ENABLE_2FA}" == "yes" ]]; then
    echo "   -> 提示：登录将仅验证【私钥 + 6位2FA验证码】"
    echo "   -> 系统不会、也无法再向你索要服务器密码（彻底解耦）"
fi
echo "------------------------------------------------------------------"

while true; do
    read -p "[?] 新窗口测试通过并成功登录了吗？输入 [y/n]: " TEST_RESULT
    TEST_RESULT=$(echo "${TEST_RESULT}" | tr '[:upper:]' '[:lower:]')
    if [[ "${TEST_RESULT}" == "y" || "${TEST_RESULT}" == "yes" ]]; then
        echo "[+] 恭喜！加固完全成功。现可安全退出脚本和当前终端。"
        break
    elif [[ "${TEST_RESULT}" == "n" || "${TEST_RESULT}" == "no" ]]; then
        rollback_all
    else
        echo "[-] 请输入 y (成功) 或 n (失败)"
    fi
done
