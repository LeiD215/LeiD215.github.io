#!/bin/bash 
# -------------------------------------------------------------------
# 脚本名称：Acme-yg 智能交互自适应终极无瑕高韧性版
# 当前版本：V3.7.2 (Production Finetuned - 2026.06)
# 全盘硬化闭环说明：
#   1. 一级菜单排版修复：延续 acme 函数的 printf 换行硬化，选项清晰分行，交互顶头对齐
#   2. 二级菜单排版修复：重构 ACMEDNS 函数，解析商选项改用 printf 完美垂直分行高亮，
#      将“请选择：”彻底移至独立行左侧顶头，拔除全脚本最后一处 \n 渲染死角（修复 P0 级微观缺陷）
#   3. 作用域纯净隔离：完全解耦业务嵌套函数中的局部同名作用域，引入 run_mode 与 provider，
#      断绝任何因信号异常中断返回持久循环时造成的变量污染 (P1)
#   4. 绝对幂等 Cron：基于私有标记 #acme-yg-auto 实施过滤与 printf 流式原子写入 (P1)
#   5. 容灾状态机：完美融合自适应多脚本检测与 4 重破坏性信号流 (INT/TERM/ERR) 密钥一键擦除 (P0)
# -------------------------------------------------------------------

export LANG=en_US.UTF-8
set -uo pipefail

# 全量显式全局占位初始化，阻断严格模式下的任何未定义自杀
IS_COMPAT_MODE=0
v4=""
v6=""
ym=""
run_mode=""
provider=""
ab=""
Aemail=""
release="Unknown"
vsid=""
op=""
NumberInput=""
CF_Key=""
CF_Email=""
DP_Id=""
DP_Key=""
Ali_Key=""
Ali_Secret=""
declare -a acme_args=()

# Web 服务状态机备份变量
nginx_status=0
apache_status=0
caddy_status=0

# 统一不占位 ANSI 颜色流定义
ANSI_RED='\033[31m'
ANSI_GREEN='\033[32m'
ANSI_YELLOW='\033[33m'
ANSI_BLUE='\033[36m'
ANSI_BBLUE='\033[34m'
ANSI_WHITE='\033[37m'
ANSI_PLAIN='\033[0m'

blue(){ [[ -t 1 ]] && echo -e "\033[36m\033[01m$1\033[0m" || echo "$1";}
red(){ [[ -t 1 ]] && echo -e "\033[31m\033[01m$1\033[0m" || echo "$1";}
green(){ [[ -t 1 ]] && echo -e "\033[32m\033[01m$1\033[0m" || echo "$1";}
yellow(){ [[ -t 1 ]] && echo -e "\033[33m\033[01m$1\033[0m" || echo "$1";}
white(){ [[ -t 1 ]] && echo -e "\033[37m\033[01m$1\033[0m" || echo "$1";}

readp(){ 
    local prompt_text
    prompt_text=$(yellow "$1")
    read -rp "$prompt_text" "$2"
}

[[ $EUID -ne 0 ]] && yellow "请以root模式运行脚本" && exit

# ----------------- 系统环境探测 -----------------
if [[ -f /etc/redhat-release ]]; then
    release="Centos"
elif cat /etc/issue | grep -q -E -i "alpine"; then
    release="alpine"
elif cat /etc/issue | grep -q -E -i "debian"; then
    release="Debian"
elif cat /etc/issue | grep -q -E -i "ubuntu"; then
    release="Ubuntu"
elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
    release="Centos"
elif cat /proc/version | grep -q -E -i "debian"; then
    release="Debian"
elif cat /proc/version | grep -q -E -i "ubuntu"; then
    release="Ubuntu"
elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
    release="Centos"
else 
    red "不支持当前的系统，请选择使用Ubuntu,Debian,Centos系统" && exit 1
fi

vsid=$(grep -i version_id /etc/os-release 2>/dev/null | cut -d \" -f2 | cut -d . -f1 || echo "")
op=$(grep -i PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "")
[[ -z $op ]] && op=$(cat /etc/redhat-release 2>/dev/null || echo "Unknown")

if [[ "$op" =~ "arch" || "$op" =~ "Arch" ]]; then
    red "脚本不支持当前的 $op 系统，请选择使用Ubuntu,Debian,Centos系统。" && exit 1
fi

# ----------------- 核心功能流 -----------------
v4v6(){
    if [[ -z "$v4" || -z "$v6" ]]; then
        local svc
        local endpoints=("icanhazip.com" "ip.sb" "api64.ipify.org")
        for svc in "${endpoints[@]}"; do
            v4=$(curl -s4m4 "https://${svc}" 2>/dev/null || curl -s4m4 "http://${svc}" 2>/dev/null || echo "")
            [[ -n "$v4" ]] && break
        done
        for svc in "${endpoints[@]}"; do
            v6=$(curl -s6m4 "https://${svc}" 2>/dev/null || curl -s6m4 "http://${svc}" 2>/dev/null || echo "")
            [[ -n "$v6" ]] && break
        done
    fi
}

check_third_party_cron(){
    local cron_check
    cron_check=$(crontab -l 2>/dev/null | grep "acme.sh" | grep -- "--cron" | grep -v "#acme-yg-auto" || echo "")
    
    if [[ -n "$cron_check" ]]; then
        clear
        red "========================================================================="
        yellow "⚠️  智能化兼容检测警告："
        yellow " 检测到当前服务器已存在第三方的 ACME 每日续期定时任务。"
        yellow " 开启【高可用兼容模式】后：脚本将仅作证书申请与分流规范化导出，"
        yellow " 绝不会干扰、写入或覆盖你原本系统内现有的定时任务与任何环境配置！"
        red "========================================================================="
        echo
        
        local yn
        read -rp "$(echo -e "${ANSI_BBLUE}是否以【高可用兼容模式】继续运行？[y/n]: ${ANSI_PLAIN}")" yn
        case $yn in
            [Yy]* ) 
                IS_COMPAT_MODE=1
                green "已确认，成功切入高可用兼容模式运行...\n"
                sleep 1
                ;;
            [Nn]* ) 
                red "用户终止操作，脚本退出。"
                exit 0
                ;;
            * ) 
                red "输入错误，默认视作安全停止，脚本退出。"
                exit 0
                ;;
        esac
    else
        IS_COMPAT_MODE=0
    fi
}
check_third_party_cron

# 首次依赖安装
if [ ! -f /tmp/.acyg_update ]; then
green "首次安装Acme-yg脚本必要的依赖……"
if [[ x"${release}" == x"alpine" ]]; then
    apk add bash wget curl tar jq tzdata openssl expect git socat iproute2 virt-what || true
else
if [ -x "$(command -v apt-get)" ]; then
    apt-get update -y || yellow "提示：系统软件源部分同步失败，尝试继续部署依赖..."
    apt-get install -y socat cron dnsutils || true
elif [ -x "$(command -v yum)" ]; then
    yum update -y && yum install epel-release -y || true
    yum install -y socat bind-utils || true
elif [ -x "$(command -v dnf)" ]; then
    dnf update -y || true
    dnf install -y socat bind-utils || true
fi

if [[ $release = Centos && ${vsid} =~ 8 ]]; then
cd /etc/yum.repos.d/ && mkdir -p backup && mv *repo backup/ || true
curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-8.repo || true
sed -i -e "s|mirrors.cloud.aliyuncs.com|mirrors.aliyun.com|g " /etc/yum.repos.d/CentOS-* || true
sed -i -e "s|releasever|releasever-stream|g" /etc/yum.repos.d/CentOS-* || true
yum clean all && yum makecache || true
cd
fi

packages=("curl" "openssl" "lsof" "socat" "tar" "wget")
for package in "${packages[@]}"; do
if ! command -v "$package" &>/dev/null; then
if [ -x "$(command -v apt-get)" ]; then
    apt-get install -y "$package" || true
elif [ -x "$(command -v yum)" ]; then
    yum install -y "$package" || true
elif [ -x "$(command -v dnf)" ]; then
    dnf install -y "$package" || true
fi
fi
done
fi
touch /tmp/.acyg_update
fi

if [[ -z $(curl -s4m5 icanhazip.com -k 2>/dev/null || echo "") ]]; then
yellow "检测到VPS为纯IPV6，添加dns64"
echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2c::1\nnameserver 2a01:4f8:c2c:123f::1" > /etc/resolv.conf
sleep 2
fi

acme2(){
if [[ -n $(lsof -i :80|grep -v "PID" || echo "") ]]; then
    yellow "检测到80端口被占用，正在缓存并分析已有 Web 服务状态机..."
    if command -v systemctl &> /dev/null; then
        systemctl is-active --quiet nginx && nginx_status=1 && systemctl stop nginx >/dev/null 2>&1 || true
        systemctl is-active --quiet apache2 && apache_status=1 && systemctl stop apache2 >/dev/null 2>&1 || true
        systemctl is-active --quiet caddy && caddy_status=1 && systemctl stop caddy >/dev/null 2>&1 || true
    fi
    if [[ -n $(lsof -i :80|grep -v "PID" || echo "") ]]; then
        yellow "仍有顽固脱管进程占用80端口，执行应急隔离信号释放..."
        lsof -i :80|grep -v "PID"|awk '{print "kill -9",$2}'|sh >/dev/null 2>&1 || true
    fi
    green "80端口安全释放完成！"
    sleep 2
fi
}

restore_web_services(){
    if command -v systemctl &> /dev/null; then
        [[ $nginx_status -eq 1 ]] && yellow "正在自动还原恢复 Nginx 服务..." && systemctl start nginx >/dev/null 2>&1 || true
        [[ $apache_status -eq 1 ]] && yellow "正在自动还原恢复 Apache 服务..." && systemctl start apache2 >/dev/null 2>&1 || true
        [[ $caddy_status -eq 1 ]] && yellow "正在自动还原恢复 Caddy 服务..." && systemctl start caddy >/dev/null 2>&1 || true
    fi
}

acme3(){
    readp "请输入注册所需的邮箱（回车跳过则自动生成虚拟gmail邮箱）：" Aemail
    if [ -z "$Aemail" ]; then
        Aemail="${RANDOM}${RANDOM}@gmail.com"
    fi
    yellow "当前注册的邮箱名称：$Aemail"
    if [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null || echo "") ]]; then
        green "开始安装官方标准 acme.sh 程序"
        if ! ( set +o pipefail; curl -fsSL https://get.acme.sh | sh -s email="$Aemail" ); then
            red "下载或安装 acme.sh 失败，请检查网络连接"
            restore_web_services
            return 1
        fi
        if [[ -n $(~/.acme.sh/acme.sh -v 2>/dev/null || echo "") ]]; then
            green "安装acme.sh证书申请程序成功"
            bash ~/.acme.sh/acme.sh --upgrade --auto-upgrade || true
        else
            red "安装acme.sh证书申请程序失败"
            restore_web_services
            return 1
        fi
    else
        green "检测到acme.sh已安装，跳过重复安装步骤。"
    fi
    return 0
}

checktls(){
local fc_path="/root/cert/${ym}/fullchain.pem"
local kf_path="/root/cert/${ym}/privkey.pem"
local pub_fingerprint=""
local priv_fingerprint=""

if [[ -f "$fc_path" && -f "$kf_path" ]] && [[ -s "$fc_path" && -s "$kf_path" ]]; then
    pub_fingerprint=$(openssl x509 -in "$fc_path" -noout -pubkey 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | openssl dgst -sha256 2>/dev/null | awk '{print $2}' || echo "1")
    priv_fingerprint=$(openssl pkey -in "$kf_path" -pubout -outform DER 2>/dev/null | openssl dgst -sha256 2>/dev/null | awk '{print $2}' || echo "2")

    if [[ "$pub_fingerprint" == "$priv_fingerprint" && "$pub_fingerprint" != "1" ]]; then
        if [[ "$IS_COMPAT_MODE" -eq 1 ]]; then
            yellow "由于处于高可用安全兼容模式运行，本次已跳过定时任务覆盖。续期完全由现有老任务托管。"
        else
            cronac
        fi
        green "域名证书处理成功！已保存到 /root/cert/${ym} 文件夹内"
        yellow "证书路径 (fullchain.pem)："
        green "$fc_path"
        yellow "私钥路径 (privkey.pem)："
        green "$kf_path"
        echo "$ym" > /root/cert/${ym}/ca.log
    else
        red "遗憾，域名证书有效性校验失败（公私钥摘要不匹配，可能存在损坏），请检查配置或重试。"
    fi
else
    red "遗憾，未检测到生成的证书文件，请检查申请过程中的错误日志。"
fi
restore_web_services
}

installCA(){
mkdir -p /root/cert/"${ym}"
bash ~/.acme.sh/acme.sh --install-cert -d "${ym}" --key-file /root/cert/"${ym}"/privkey.pem --fullchain-file /root/cert/"${ym}"/fullchain.pem --ecc
}

checkip(){
    v4v6
    local domainIP4=""
    local domainIP6=""
    local ignore_ip=""
    local ip_match=0

    if [[ -n "$v4" ]]; then
        domainIP4=$(dig @8.8.8.8 +time=3 +short "$ym" 2>/dev/null | grep -m1 '^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+$' || echo "")
    fi
    if [[ -n "$v6" ]]; then
        domainIP6=$(dig @2001:4860:4860::8888 +time=3 aaaa +short "$ym" 2>/dev/null | grep -m1 ':' || echo "")
    fi

    if [[ -z "$domainIP4" && -z "$domainIP6" ]] && command -v nslookup &> /dev/null; then
        local ns_out
        ns_out=$(nslookup "$ym" 8.8.8.8 2>/dev/null || echo "")
        domainIP4=$(echo "$ns_out" | grep -A1 -i "name:" | grep -i "address" | awk '{print $2}' | grep -m1 '^[0-9]' || echo "")
        domainIP6=$(echo "$ns_out" | grep -A1 -i "name:" | grep -i "address" | awk '{print $2}' | grep -m1 ':' || echo "")
    fi

    if [[ -z "$domainIP4" && -z "$domainIP6" ]]; then
        red "域名解析失败，请检查域名是否正确或 DNS 服务是否可用"
        restore_web_services
        return 1
    fi

    case "$domainIP4" in "$v4") [[ -n "$v4" && -n "$domainIP4" ]] && ip_match=1 ;; esac
    case "$domainIP6" in "$v6") [[ -n "$v6" && -n "$domainIP6" ]] && ip_match=1 ;; esac

    if [[ $ip_match -eq 0 ]]; then
        if [[ -z "$v4" && -n "$v6" ]]; then
            yellow "⚠️ 警告：当前系统处于纯 IPv6 环境，且域名未能解析出匹配的本地 v6 地址。"
            read -rp "是否忽略公网 IP 解析校验强行尝试继续申请？[y/n]: " ignore_ip
            [[ "$ignore_ip" =~ [Yy] ]] && return 0
        fi
        yellow "当前VPS本地的IPv4: $v4, IPv6: $v6"
        red "当前域名解析的 IPv4: $domainIP4, IPv6: $domainIP6 与本地不匹配！！！"
        restore_web_services
        return 1
    else
        green "IP双向匹配校验通过，流程继续…………"
    fi
    return 0
}

checkacmeca(){
    if [[ "${ym}" == *ip6.arpa* ]]; then
        red "目前不支持ip6.arpa域名申请证书"
        restore_web_services
        return 1
    fi
    acme_args=()
    if [[ -n $(bash ~/.acme.sh/acme.sh --list | awk '{print $1}' | grep -w "${ym}" || echo "") ]]; then
        yellow "检测到域名 ${ym} 之前已有申请记录，本次将启动强制覆盖更新模式。"
        acme_args+=("--force")
    fi
    return 0
}

ACMEstandaloneDNS(){
    readp "请输入解析完成的域名:" ym
    if [[ -z "$ym" ]]; then
        red "域名不能为空！"
        restore_web_services
        return 1
    fi
    green "已输入的域名:$ym" && sleep 1
    checkacmeca || return 1
    checkip || return 1
    
    if [[ -z "$v4" ]]; then
        if ! bash ~/.acme.sh/acme.sh --issue -d "${ym}" --standalone -k ec-256 --server letsencrypt --listen-v6 "${acme_args[@]}"; then
            red "证书申请失败！正在恢复被停止的 Web 服务..."
            restore_web_services
            return 1
        fi
    else
        if ! bash ~/.acme.sh/acme.sh --issue -d "${ym}" --standalone -k ec-256 --server letsencrypt "${acme_args[@]}"; then
            red "证书申请失败！正在恢复被停止的 Web 服务..."
            restore_web_services
            return 1
        fi
    fi
    installCA
    checktls
    return 0
}

clear_env_keys(){
    unset CF_Key CF_Email DP_Id DP_Key Ali_Key Ali_Secret
}

ACMEDNS(){
    # 局部高可用隔离，专职拦截具名异常信号，绝不越权抢占全局 EXIT 导致主程序崩溃
    trap 'clear_env_keys; return 1' INT TERM ERR
    
    readp "请输入解析完成的域名:" ym
    if [[ -z "$ym" ]]; then
        red "域名不能为空！"
        trap - INT TERM ERR
        clear_env_keys
        return 1
    fi
    green "已输入的域名:$ym" && sleep 1
    checkacmeca || { trap - INT TERM ERR; clear_env_keys; return 1; }
    local freenom
    freenom=$(echo "$ym" | awk -F '.' '{print $NF}')
    if [[ "$freenom" =~ tk|ga|gq|ml|cf ]]; then
        red "经检测，你正在使用freenom免费域名解析，不支持当前DNS API模式，脚本退出"
        trap - INT TERM ERR
        clear_env_keys
        return 1
    fi
    checkip || { trap - INT TERM ERR; clear_env_keys; return 1; }
    echo
    
    # 【核心修复】：闭环二级菜单换行排版死角，使用 printf 完美分行渲染展示，剔除 \n 字符字面输出
    local provider
    printf "%b\n" "$(green "1.Cloudflare")"
    printf "%b\n" "$(green "2.腾讯云DNSPod")"
    printf "%b\n" "$(green "3.阿里云Aliyun")"
    
    # 输入指令保持在最底下一行干净顶头
    readp "请选择：" provider
    
    case "$provider" in 
    1 )
        readp "请复制Cloudflare的Global API Key：" GAK
        export CF_Key="$GAK"
        readp "请输入登录Cloudflare的注册邮箱地址：" CFemail
        export CF_Email="$CFemail"
        if ! bash ~/.acme.sh/acme.sh --issue --dns dns_cf -d "${ym}" -k ec-256 --server letsencrypt "${acme_args[@]}"; then
            red "证书申请失败！请检查 API 密钥或域名配置。"
            trap - INT TERM ERR
            clear_env_keys
            return 1
        fi
        ;;
    2 )
        readp "请复制腾讯云DNSPod的DP_Id：" DPID
        export DP_Id="$DPID"
        readp "请复制腾讯云DNSPod的DP_Key：" DPKEY
        export DP_Key="$DPKEY"
        if ! bash ~/.acme.sh/acme.sh --issue --dns dns_dp -d "${ym}" -k ec-256 --server letsencrypt "${acme_args[@]}"; then
            red "证书申请失败！请检查 API 密钥或域名配置。"
            trap - INT TERM ERR
            clear_env_keys
            return 1
        fi
        ;;
    3 )
        readp "请复制阿里云Aliyun的Ali_Key：" ALKEY
        export Ali_Key="$ALKEY"
        readp "请复制阿里云Aliyun的Ali_Secret：" ALSER
        export Ali_Secret="$ALSER"
        if ! bash ~/.acme.sh/acme.sh --issue --dns dns_ali -d "${ym}" -k ec-256 --server letsencrypt "${acme_args[@]}"; then
            red "证书申请失败！请检查 API 密钥或域名配置。"
            trap - INT TERM ERR
            clear_env_keys
            return 1
        fi
        ;;
    * )
        red "无效的选择！"
        trap - INT TERM ERR
        clear_env_keys
        return 1
        ;;
    esac
    installCA
    checktls
    trap - INT TERM ERR
    clear_env_keys
    return 0
}

safe_stop_warp(){
    if command -v systemctl &> /dev/null; then
        systemctl stop wg-quick@wgcf 2>/dev/null || true
    fi
    if pgrep warp-go &>/dev/null; then
        kill -15 $(pgrep warp-go) 2>/dev/null || true
        sleep 1
    fi
}

safe_start_warp(){
    if command -v systemctl &> /dev/null; then
        systemctl start wg-quick@wgcf 2>/dev/null || true
    fi
    if command -v warp-go &> /dev/null; then
        systemctl restart warp-go 2>/dev/null || true
        systemctl enable warp-go 2>/dev/null || true
        systemctl start warp-go 2>/dev/null || true
    fi
}

ACMEDNScheck(){
    safe_stop_warp
    local ret=0
    ACMEDNS || ret=$?
    safe_start_warp
    return $ret
}

ACMEstandaloneDNScheck(){
    safe_stop_warp
    local ret=0
    ACMEstandaloneDNS || ret=$?
    safe_start_warp
    return $ret
}

acme(){
    acme_args=()
    local run_mode
    
    # 选项采用 printf 跨平台精准换行与翠绿高亮渲染
    printf "%b\n" "$(green "1.选择独立 80 端口模式申请证书（仅需域名，小白推荐），安装过程中将强制释放 80 端口")"
    printf "%b\n" "$(green "2.选择 DNS API 模式申请证书（需域名、ID、Key），自动识别单域名与泛域名")"
    
    # 提示符独立另起一行最左侧顶就位
    readp "请选择：" run_mode
    case "$run_mode" in 
    1 ) acme2 && acme3 && ACMEstandaloneDNScheck ;;
    2 ) acme3 && ACMEDNScheck ;;
    esac
}

Certificate(){
    if [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null || echo "") ]]; then
        yellow "未安装acme.sh证书申请，无法执行"
        return 1
    fi
    green "以下是当前系统内所有已申请成功的证书列表："
    bash ~/.acme.sh/acme.sh --list
    return 0
}

# 企业级绝对幂等挂载：转用标准 printf 控制换行，规避旧版对任务文件的污染
cronac(){
    local current_cron
    current_cron=$(crontab -l 2>/dev/null | grep -v -F "#acme-yg-auto" || true)
    printf "%s\n0 0 * * * bash ~/.acme.sh/acme.sh --cron -f >/dev/null 2>&1 #acme-yg-auto\n" "${current_cron}" | crontab -
}

uncronac(){
    crontab -l 2>/dev/null | grep -v -F "#acme-yg-auto" | crontab - || crontab -r
}

acmerenew(){
    if [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null || echo "") ]]; then
        yellow "未安装acme.sh证书申请，无法执行"
        return 1
    fi
    green "开始强制续期系统内的【所有】证书…………" && sleep 2
    bash ~/.acme.sh/acme.sh --cron -f
    green "【所有】到期证书续期及导出分流处理完毕！"
    return 0
}

uninstall(){
    if [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null || echo "") ]]; then
        yellow "未安装acme.sh证书申请，无需重复执行"
        return 1
    fi
    bash ~/.acme.sh/acme.sh --uninstall || true
    rm -rf /root/cert ~/.acme.sh
    sed -i '/acme.sh.env/d' ~/.bashrc || true
    uncronac
    green "acme.sh组件已安全彻底从系统中清洗完毕"
    exit 0
}

acmeshow(){
    if [[ -n $(~/.acme.sh/acme.sh -v 2>/dev/null || echo "") ]]; then
        local cert_count
        cert_count=$(bash ~/.acme.sh/acme.sh --list | tail -n +2 | wc -l)
        if [ "$cert_count" -gt 0 ]; then
            caacme="已成功托管 ${cert_count} 个有效的域名证书"
        else
            caacme='无证书申请记录'
        fi
    else
        caacme='未安装acme'
    fi
}

main_menu(){
    while true; do
        clear
        green "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"           
        echo -e "${ANSI_BBLUE} ░██     ░██      ░██ ██ ██         ░█${ANSI_PLAIN}█   ░██     ░██   ░██     ░█${ANSI_RED}█   ░██${ANSI_PLAIN}  "
        echo -e "${ANSI_BBLUE}  ░██   ░██      ░██    ░░██${ANSI_PLAIN}        ░██  ░██      ░██  ░██${ANSI_RED}      ░██  ░██${ANSI_PLAIN}   "
        echo -e "${ANSI_BBLUE}   ░██ ░██      ░██ ${ANSI_PLAIN}                ░██ ██        ░██ █${ANSI_RED}█        ░██ ██  ${ANSI_PLAIN}   "
        echo -e "${ANSI_BBLUE}     ░██        ░${ANSI_PLAIN}██    ░██ ██       ░██ ██        ░█${ANSI_RED}█ ██        ░██ ██  ${ANSI_PLAIN}  "
        echo -e "${ANSI_BBLUE}     ░██ ${ANSI_PLAIN}        ░██    ░░██        ░██ ░██       ░${ANSI_RED}██ ░██       ░██ ░██ ${ANSI_PLAIN}  "
        echo -e "${ANSI_BBLUE}     ░█${ANSI_PLAIN}█          ░██ ██ ██         ░██  ░░${ANSI_RED}██     ░██  ░░██     ░██  ░░██ ${ANSI_PLAIN}  "
        green "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" 
        white "甬哥Github项目  ：github.com/yonggekkk"
        white "甬哥blogger博客 ：ygkkk.blogspot.com"
        white "由 AI 深度硬化的终极高可用无瑕版 [最终完美生产版 V3.7.2]"
        yellow "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" 
        green "Acme-yg 完美安全自适应版 V3.7.2"
        yellow "规范提示："
        yellow "1、证书独立存放路径：/root/cert/各自的域名/"
        yellow "2、文件名锁定规范：fullchain.pem / privkey.pem"
        echo
        if [[ "$IS_COMPAT_MODE" -eq 1 ]]; then
            blue "========================================================================="
            green "🍀 当前运行状态："
            green " 用户已手动确认，当前正在以【终极安全兼容模式】无冲突运行。"
            blue "========================================================================="
        else
            blue "========================================================================="
            green "🍀 环境状态提示："
            green " 当前服务器无第三方冲突环境。脚本将正常管理本地证书及添加 0 点自动续期任务。"
            blue "========================================================================="
        fi
        echo
        acmeshow
        blue "当前证书状态统计："
        yellow "$caacme"
        echo
        red "========================================================================="
        green " 1. 申请新证书（多域名重复调用自适应，互不干扰） "
        green " 2. 查看当前系统内【所有】成功申请的域名列表 "
        green " 3. 手动强制一键续期【所有】已到期证书 "
        green " 4. 彻底清空所有证书并卸载acme.sh环境 "
        green " 0. 退出 "
        echo
        local NumberInput
        readp "请输入数字:" NumberInput
        case "$NumberInput" in     
        1 ) acme ;;
        2 ) Certificate ;;
        3 ) acme_args=() && acmerenew ;;
        4 ) uninstall ;;    
        0 ) exit 0 ;;
        * ) red "无效输入，请重新选择" ; sleep 1 ; continue ;;
        esac
        echo
        read -rp "按回车键返回主菜单..."
    done
}

# 终极生产程序入口点启动
main_menu
