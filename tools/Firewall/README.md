# 小白（就是我）自用的防火墙设置脚本

## Usage

First of all, download the main script:
```
{ curl -sSL https://github.com/LeiD215/LeiD215.github.io/raw/refs/heads/master/tools/Firewall/firewall.sh > firewall.sh || wget -qO firewall.sh https://github.com/LeiD215/LeiD215.github.io/raw/refs/heads/master/tools/Firewall/firewall.sh; } && chmod +x firewall.sh && sudo ./firewall.sh
```

GEMINI搞出来的，记录一下，试试效果。

一、 核心架构：全自动运维
脚本采用环境自适应机制，运行后自动执行以下全自动流程：

智能识别：自动判断系统是 Debian/Ubuntu 还是 CentOS/RHEL 系列。

冲突清理：交互式卸载旧防火墙，强力清空残留的旧 iptables 规则链。

精准纳管：在 Debian/Ubuntu 下默认安装并启用 UFW；在 RHEL 系列下默认安装并启用 Firewalld。

二、 三大安全防御保障
为了保障服务器在配置期间的安全与稳定，脚本内置了三重安全策略：

SSH 智能抓取：自动读取内核网络栈，精准提取当前系统真实监听的 SSH 端口。

终极防锁死：初始化时默认阻断所有外部入站流量，仅放行 SSH 端口，确保管理员不掉线。

IPv6 路由加固：开启 IPv6 转发时自动追加 accept_ra=2 内核参数，彻底杜绝部分动态机房服务器因开启转发而导致 IPv6 断网、丢 IP 的隐蔽大坑。

三、 四大全能交互模块
进入主菜单后，通过极简的中文交互，提供四大核心业务能力：

协议全能：支持 TCP、UDP、TCP+UDP（两者都要）的一键切换。

栈别全能：支持 IPv4、IPv6、IPv4+IPv6（双栈都要）的灵活应用。

端口全能：支持单个端口（如 80）或连续端口段（如 8000:8010）的批量开启与关闭。

转发全能：智能使能底层内核转发（ip_forward），完美支持 “本机内部端口映射” 与 “跨服务器外部转发” 两种场景。在 UFW 环境下自动调用 iptables -t nat 引擎二次加固，并实现长效持久化防丢失。
