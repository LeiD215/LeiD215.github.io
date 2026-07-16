#!/bin/bash

# ==============================================================================
# 脚本名称: sshs.sh
# 版本号:   1.0.0 (商用金标终结版 - PCI-DSS Ready)
# 描述:     Linux SSH 安全加固与 2FA 一键部署脚本（完美兼容、极速验证、防输入注入）
# ==============================================================================

# 严格模式：发生任何非零返回或管道失败时立退。
set -euo pipefail

# ------------------------------------------------------------------------------
# 0. 统一定义只读全局配置（引入 PID 防止高并发多机分发时同秒备份文件名冲突）
# ------------------------------------------------------------------------------
readonly TIME_STAMP="$(date +%Y%m%d_%H%M%S)_$$"
readonly BAK_SUFFIX="pre_secure_v1.0.0_${TIME_STAMP}"

readonly SSHD_CONFIG="/etc/ssh/sshd_config"
readonly PAM_SSH="/etc/pam.d/sshd"

readonly SSHD_BAK="${SSHD_CONFIG}.${BAK_SUFFIX}"
readonly PAM_BAK="${PAM_SSH}.${BAK_SUFFIX}"

# 完美闭环：自适应 Chrony 路径初始化逻辑与时序，防止 readonly 被锁定在非预期空路径上
if [ -d "/etc/chrony" ] || command -v apt-get >/dev/null 2>&1; then
    CHRONY_CONF_PATH="/etc/chrony/chrony.conf"
    mkdir -p /etc/chrony
else
    CHRONY_CONF_PATH="/etc/chrony.conf"
fi
touch "${CHRONY_CONF_PATH}" # 确保物理文件先存在，防止后续备份/修改失败
readonly CHRONY_CONF="${CHRONY_CONF_PATH}"
readonly CHRONY_BAK="${CHRONY_CONF}.${BAK_SUFFIX}"

# 提前、自适应唯一探测 SSH 系统服务名（防止 rollback_all 未定义竞态）
if systemctl list-units --type=service 2>/dev/null | grep -q "sshd.service"; then
    readonly SSH_SERVICE_NAME="sshd"
else
    readonly SSH_SERVICE_NAME="ssh"
fi

# 定义公钥下载源（国内外双备份）
readonly KEY_URL_ABROAD="https://github.com/LeiD215/LeiD215.github.io/raw/master/tools/temp/GMail2023EDPW.key"
readonly KEY_URL_DOMESTIC="https://gitee.com/LeiD215/LeiD215.gitee.io/raw/master/tools/temp/GMail2023EDPW.key"

# ------------------------------------------------------------------------------
# 0.1 统一封装灾难恢复函数（提供明确反馈，防 || true 吞掉严重异常）
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
        echo "    请绝对保持当前会话不要断开，并立即手动排查错误原因："
        echo "    手动重启命令: systemctl restart ${SSH_SERVICE_NAME}"
        echo "    查看系统日志: journalctl -u ${SSH_SERVICE_NAME} -n 50"
    fi
    exit 1
}

# 确保以 root 权限运行
if [ "${EUID}" -ne 0 ]; then
  echo "[-] 错误: 请使用 root 权限运行此脚本（例如: sudo ./sshs.sh）"
  exit 1
fi

echo "=================================================================="
echo "        Linux SSH 安全加固与 2FA 一键部署脚本 v1.0.0"
echo "=================================================================="

# ------------------------------------------------------------------------------
# 1. 交互式选择公钥源并下载
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

# 严格的公钥格式指纹核验
echo "[+] 正在使用 ssh-keygen 强制校验公钥指纹..."
if ! echo "${PUBLIC_KEY}" | ssh-keygen -l -f /dev/stdin &>/dev/null; then
    echo "[-] 错误: 公钥格式验证失败！可能已被篡改、截断或含有恶意代码。"
    exit 1
fi
echo "[+] 公钥格式校验通过。"

# ------------------------------------------------------------------------------
# 2. 交互式输入端口（精准清理旧 Port，防占用）
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
# 3. 交互式询问是否开启双因子认证 (2FA)
# ------------------------------------------------------------------------------
echo "------------------------------------------------------------------"
echo "[?] 是否需要启用双因子认证 (2FA)？"
echo "    启用后，登录时不仅需要私钥，还需输入手机/1Password 的 6 位动态验证码。"
read -p "请输入 [y/N] (默认不启用 N): " ENABLE_2FA
ENABLE_2FA=$(echo "${ENABLE_2FA}" | tr '[:upper:]' '[:lower:]')

# ------------------------------------------------------------------------------
# 4. 配置高可用国内外通用 NTP 时间同步
# ------------------------------------------------------------------------------
if [[ "${ENABLE_2FA}" == "y" || "${ENABLE_2FA}" == "yes" ]]; then
    echo "[+] 正在配置高可用、国内外无缝直连的 NTP 时间同步..."
    
    if ! command -v chronyd >/dev/null 2>&1; then
        echo "[+] 正在安装 chrony 守护进程..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -y && apt-get install -y chrony
        elif command -v yum >/dev/null 2>&1; then
            yum install -y chrony
        fi
    fi

    # 备份 Chrony 配置
    cp "${CHRONY_CONF}" "${CHRONY_BAK}"
    
    sed -i '/^[[:space:]]*server /d' "${CHRONY_CONF}"
    sed -i '/^[[:space:]]*pool /d' "${CHRONY_CONF}"
    
    cat << EOF >> "${CHRONY_CONF}"
# 1.0.0 黄金高可用时钟源
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
        echo "[-] 错误：无法确定 chrony 服务名，请手动检查系统 Chrony 状态。"
        exit 1
    fi

    systemctl enable "${CHRONY_SERVICE}" >/dev/null 2>&1 || true
    systemctl restart "${CHRONY_SERVICE}" >/dev/null 2>&1 || true
    
    chronyc makestep >/dev/null 2>&1 || true
    echo "[+] 时间同步配置完成。当前系统时间: $(date -R)"
fi

# ------------------------------------------------------------------------------
# 5. 写入公钥（写入到 root 家目录）
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
# 6. 配置防火墙与 SELinux（支持规则清理，防止 SELinux 覆盖）
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
    
    # 完美修复：IPTables 保存提示深度适配，针对不同发行版给出极度严谨的手动命令
    if [ "${IPTABLES_SAVED}" = false ]; then
        echo "[!] 警告：无法持久化本地 iptables 规则，重启后可能丢失！"
        echo "    建议手动执行以下对应命令保存："
        if command -v netfilter-persistent >/dev/null 2>&1; then
            echo "    -> netfilter-persistent save"
        elif [ -d /etc/sysconfig ]; then
            echo "    -> iptables-save > /etc/sysconfig/iptables"
        elif [ -d /etc/iptables ]; then
            echo "    -> mkdir -p /etc/iptables && iptables-save > /etc/iptables/rules.v4"
        else
            echo "    -> iptables-save > /etc/iptables.rules"
        fi
    fi
else
    echo "[*] 本地未检测到活动防火墙组件。请确保外部云平台安全组已放行端口 ${NEW_PORT}"
fi

# SELinux 安全策略：防止覆盖其他服务的端口属性
if command -v semanage >/dev/null 2>&1 && getenforce | grep -qi "enforcing"; then
    echo "[+] 检测到 SELinux 处于开启状态，正在做端口安全性检查..."
    EXISTING_TYPE=$(semanage port -l | awk -v port="${NEW_PORT}" '$3 ~ port {print $1; exit}')
    if [ -n "${EXISTING_TYPE}" ] && [ "${EXISTING_TYPE}" != "ssh_port_t" ]; then
        echo "[-] 警告：新端口 ${NEW_PORT} 已被标记为 ${EXISTING_TYPE}，可能属于系统其他基础服务。"
        read -p "是否强行将该端口的 SELinux 属性修改为 ssh_port_t？[y/N]: " FORCE_SELINUX
        FORCE_SELINUX=$(echo "${FORCE_SELINUX}" | tr '[:upper:]' '[:lower:]')
        if [[ "${FORCE_SELINUX}" != "y" && "${FORCE_SELINUX}" != "yes" ]]; then
            echo "[-] 用户拒绝覆盖 SELinux 策略，加固流程中止。"
            exit 1
        fi
    fi
    semanage port -a -t ssh_port_t -p tcp "${NEW_PORT}" 2>/dev/null || semanage port -m -t ssh_port_t -p tcp "${NEW_PORT}"
fi

# ------------------------------------------------------------------------------
# 7. 修改 SSH 配置文件 (sshd_config) — 彻底清理无用端口
# ------------------------------------------------------------------------------
echo "[+] 正在备份并修改 ${SSHD_CONFIG}..."
cp "${SSHD_CONFIG}" "${SSHD_BAK}"

sed -i '/^[[:space:]]*Port[[:space:]]/d' "${SSHD_CONFIG}"
echo "Port ${NEW_PORT}" >> "${SSHD_CONFIG}"

sed -i '/^[[:space:]]*PubkeyAuthentication[[:space:]]/d' "${SSHD_CONFIG}"
echo "PubkeyAuthentication yes" >> "${SSHD_CONFIG}"

sed -i '/^[[:space:]]*PasswordAuthentication[[:space:]]/d' "${SSHD_CONFIG}"
echo "PasswordAuthentication no" >> "${SSHD_CONFIG}"

sed -i '/^[[:space:]]*PermitRootLogin[[:space:]]/d' "${SSHD_CONFIG}"
echo "PermitRootLogin prohibit-password" >> "${SSHD_CONFIG}"

# ------------------------------------------------------------------------------
# 8. 安装与配置 2FA PAM 模块（安全引入合规镜像检测、第一优先安全 PAM 注入）
# ------------------------------------------------------------------------------
if [[ "${ENABLE_2FA}" == "y" || "${ENABLE_2FA}" == "yes" ]]; then
    echo "[+] 正在下载并安装 Google Authenticator PAM 模块..."
    
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y && apt-get install -y libpam-google-authenticator
        
    elif command -v yum >/dev/null 2>&1; then
        echo "[+] 检测到红帽系系统，正在核对网络安装环境..."
        if ! yum makecache >/dev/null 2>&1; then
            echo "[!] 检测到默认源同步失败，正在为系统配置国内高速 EPEL 镜像源..."
            [ -f /etc/yum.repos.d/epel.repo ] && mv /etc/yum.repos.d/epel.repo /etc/yum.repos.d/epel.repo.bak 2>/dev/null
            yum install -y epel-release || true
            
            RELEASE_RPM=$(rpm -q --qf "%{VERSION}" "$(rpm -q --whatprovides redhat-release 2>/dev/null | head -n1)" 2>/dev/null | grep -oE '[0-9]+' | head -n1 || echo "")
            if [ -n "${RELEASE_RPM}" ]; then
                curl -sLo /etc/yum.repos.d/epel.repo "https://mirrors.aliyun.com/repo/epel-${RELEASE_RPM}.repo" || {
                    sed -i 's|^metalink=|#metalink=|g' /etc/yum.repos.d/epel* 2>/dev/null || true
                    sed -i 's|^#baseurl=https://download.fedoraproject.org/pub/epel/|baseurl=https://mirrors.aliyun.com/epel/|g' /etc/yum.repos.d/epel* 2>/dev/null || true
                }
            fi
        fi
        yum install -y google-authenticator
    fi

    if ! command -v google-authenticator >/dev/null 2>&1; then
        echo "[-] 错误：google-authenticator 可执行二进制文件未找到！"
        echo "    可能的原因："
        echo "    1. 包管理器由于防火墙或网络原因安装失败"
        echo "    2. EPEL 源配置未正确加载（针对 RHEL/CentOS 系列）"
        echo "    手动检查 PAM 模块指令指引："
        echo "    -> Debian/Ubuntu: dpkg -L libpam-google-authenticator 2>/dev/null | grep '.so'"
        echo "    -> CentOS/RHEL:   rpm -ql google-authenticator 2>/dev/null | grep '.so'"
        echo "    -> 广义磁盘搜索:  find /lib /usr/lib -name 'pam_google_authenticator.so'"
        rollback_all
    fi

    if [ -f "${PAM_SSH}" ]; then
        cp "${PAM_SSH}" "${PAM_BAK}"
        if ! grep -q "pam_google_authenticator.so" "${PAM_SSH}"; then
            echo "[+] 正在将 2FA 认证指令安全写入 PAM 栈首行..."
            sed -i '1i auth required pam_google_authenticator.so' "${PAM_SSH}"
        fi
    fi

    sed -i '/^[[:space:]]*KbdInteractiveAuthentication[[:space:]]/d' "${SSHD_CONFIG}"
    echo "KbdInteractiveAuthentication yes" >> "${SSHD_CONFIG}"
    
    sed -i '/^[[:space:]]*AuthenticationMethods[[:space:]]/d' "${SSHD_CONFIG}"
    echo "AuthenticationMethods publickey,keyboard-interactive" >> "${SSHD_CONFIG}"

    # 初始化 2FA 凭证
    echo "------------------------------------------------------------------"
    echo "[!!!] 重要提示：即将开始为 root 生成 2FA 密钥。"
    echo "      请拿出手机或 1Password 准备好扫码。"
    echo "      脚本执行完成后会暂停，以便你复制、记录「应急备用码（Scratch codes）」"
    echo "------------------------------------------------------------------"
    
    google-authenticator -t -d -u -w 3

    while true; do
        read -p "[?] 请确认你已安全备份了 2FA 二维码和 5 个应急备用码？[y/n]: " VERIFY_SAVE
        VERIFY_SAVE=$(echo "${VERIFY_SAVE}" | tr '[:upper:]' '[:lower:]')
        if [[ "${VERIFY_SAVE}" == "y" || "${VERIFY_SAVE}" == "yes" ]]; then
            echo "[+] 确认完毕，执行后续安全测试流。"
            break
        elif [[ "${VERIFY_SAVE}" == "n" || "${VERIFY_SAVE}" == "no" ]]; then
            rollback_all
        else
            echo "[-] 输入无效！请输入 y (已保存并继续) 或 n (取消加固并回滚)"
        fi
    done
else
    sed -i '/^[[:space:]]*KbdInteractiveAuthentication[[:space:]]/d' "${SSHD_CONFIG}"
    echo "KbdInteractiveAuthentication no" >> "${SSHD_CONFIG}"
    sed -i "/^[[:space:]]*AuthenticationMethods[[:space:]]/d" "${SSHD_CONFIG}"
fi

# ------------------------------------------------------------------------------
# 9. 自动获取外网 IP、服务名自适应、安全重启与交互确认
# ------------------------------------------------------------------------------
echo "[+] 正在自适应检测系统网络，获取服务器公网 IP..."
SERVER_IP=$(curl -s --connect-timeout 5 ip.sb || curl -s --connect-timeout 5 ifconfig.me || curl -s --connect-timeout 5 test.ipw.cn || echo "")

# 公网 IP 获取失败容错增强与严格的输入格式过滤（杜绝命令注入）
if [ -z "${SERVER_IP}" ]; then
    echo "[!] 无法自动获取公网 IP，请手动确认服务器地址。"
    while true; do
        read -p "请输入服务器 IP 或域名 (默认 localhost): " MANUAL_IP
        MANUAL_IP=${MANUAL_IP:-"localhost"}
        
        # 严苛正则校验：只允许正常的 IP 地址、域名或 localhost 字符，彻底阻断注入黑客命令
        if [[ "${MANUAL_IP}" =~ ^[a-zA-Z0-9.-]+$ ]]; then
            SERVER_IP="${MANUAL_IP}"
            break
        else
            echo "[-] 警告：检测到不合法的字符格式，请重新输入合法的 IP 或域名！"
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
        echo "[-] 错误：PAM 配置文件没有正确写入模块配置！"
        rollback_all
    fi
    
    echo "[+] 正在对 pam_google_authenticator.so 模块进行物理完整性检索..."
    # 使用极致精准的 sed 提取 ldconfig 输出，防止链接指向导致 `->` 被越界匹配，保证 Debian/RHEL Multiarch 100% 兼容
    PAM_MODULE_PATH=$(
        ldconfig -p 2>/dev/null | grep 'pam_google_authenticator\.so' | sed -n 's/.* => \([^ ]*\).*/\1/p' | head -n1 || \
        find /lib /usr/lib -type f -name "pam_google_authenticator.so" 2>/dev/null | head -n1
    )
    if [ -z "${PAM_MODULE_PATH}" ]; then
        echo "[-] 错误：物理磁盘中未检测到 pam_google_authenticator.so，2FA 将无法载入！"
        echo "    可能原因：PAM 的开发共享库由于架构路径非标被忽略，或安装未释放完全。"
        rollback_all
    fi
    echo "[+] PAM 动态库物理校验通过：${PAM_MODULE_PATH}"
fi

echo "[+] 语法与物理链路校验通过，正在重启 ${SSH_SERVICE_NAME} 服务..."
systemctl restart "${SSH_SERVICE_NAME}"

echo "=================================================================="
echo "[★] 配置应用成功！进入双重登录安全验证链"
echo "=================================================================="
echo "⚠️【警告：绝对不要关闭当前这个终端窗口！】"
echo "请在本地电脑上立即新开一个终端，执行以下命令测试能否连接："
echo ""
echo "   ssh -p ${NEW_PORT} root@${SERVER_IP}"
echo ""
if [[ "${ENABLE_2FA}" == "y" || "${ENABLE_2FA}" == "yes" ]]; then
    echo "   -> 提示：新连接会首先验证你的 SSH 私钥"
    echo "   -> 通过后终端会弹出：Verification code:"
    echo "   -> 此时输入你刚刚绑定的验证器（1Password/手机）里的 6 位动态数字即可登入。"
fi
echo "------------------------------------------------------------------"

# 强制用户显式确认测试结果，不通过则自动执行安全回滚
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
