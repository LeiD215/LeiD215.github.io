# sshs.sh (v1.0.0)

`sshs.sh` 是一个专为 Linux 服务器设计的 SSH 安全加固与 2FA（双因子认证）一键部署脚本。脚本在保障系统安全的同时，引入了**金融级防锁死安全网**与**自愈式回滚机制**，满足 PCI-DSS 等企业安全合规审计标准。

---

## 🛡️ 核心安全特性

1. **零注入防御**：
* 交互式输入端口与 IP 地址时，引入严格的正则过滤 `^[a-zA-Z0-9.-]+$`，彻底阻断利用终端输入进行命令拼接与代码注入的风险。


2. **安全链置顶（PAM 栈强制防御）**：
* 自动在 `/etc/pam.d/sshd` 栈首行精准插入 `pam_google_authenticator.so`。获得最高安全拦截权，防止由于其他冗余 include 认证链导致 2FA 被绕过。


3. **物理完整性校验（防静默锁死）**：
* 重启服务前，脚本会自动利用 `ldconfig` 极速定位与递归检索，在系统所有动态库路径（兼容 Multiarch，如 Ubuntu 的 `/usr/lib/x86_64-linux-gnu/security/`）下进行 `pam_google_authenticator.so` 物理文件检索。若磁盘中无此文件，脚本将安全拒绝并触发回滚，杜绝因 PAM 模块缺失导致的登录死锁。


4. **自愈回滚机制**：
* 脚本运行中如果测试连接失败（输入 `n`），或语法校验未通过，将立即启动**物理回滚**：复原 `sshd_config`、`PAM` 及 `Chrony` 配置，清理临时 2FA 运行时令牌，并给出显式状态提示。


5. **高并发与跨天兼容**：
* 备份文件引入精确时间戳与进程 PID 锁（格式为 `_YYYYMMDD_HHMMSS_$$`），防止在大规模自动化并发配置（如 Ansible/SaltStack）时同秒生成重名备份，且能平滑避开跨午夜的经典时间差 Bug。



---

## 🛠️ 功能概览

* **SSH 基础加固**：
* 修改默认 SSH 端口（支持占用检测与安全范围限制）。
* 强制禁用密码登录，仅允许 Root 通过密钥安全登录（`PermitRootLogin prohibit-password`）。
* 自动导入指定公钥（使用 `ssh-keygen -l` 对下载的公钥进行数学物理指纹核验）。


* **多因子安全 (2FA)**：
* 强制声明 `AuthenticationMethods publickey,keyboard-interactive`。
* 自动安装配置 Google Authenticator 服务。
* 自动配置 Apple、阿里、腾讯、Cloudflare 高可用 NTP 服务，保证 2FA 令牌时间精度，滑窗容错设置为 3 分钟。


* **网络与策略自适应**：
* **防火墙**：自动循环清空 INPUT 链上所有的 22 端口转发规则，支持并适配 UFW、Firewalld 及原生 iptables（未持久化时提供具体系统命令提示）。
* **SELinux**：自动扫描新端口是否已被其他服务（如 Nginx `http_port_t`）打标占用，防止因暴力覆盖导致基础服务崩溃。



---

## 🖥️ 兼容性说明

脚本已在以下主流 64 位 Linux 发行版中通过了严格的边界测试：

* **Debian/Ubuntu 系列**：Debian 10/11/12、Ubuntu 20.04/22.04/24.04 及更新版本（完全兼容 Multiarch 目录）
* **红帽/企业级系列**：CentOS 7/8/9、Rocky Linux 8/9、AlmaLinux 8/9
* **定制版系统**：Amazon Linux（兼容非标 PAM / 服务的特殊配置路径）

---

## 🚀 部署命令

### 1. 极简无残留版（推荐）

保持传输层 SSL 强校验，不产生临时 `.sh` 物理文件：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/LeiD215/LeiD215.github.io/master/tools/sshs/sshs.sh || wget -qO- https://raw.githubusercontent.com/LeiD215/LeiD215.github.io/master/tools/sshs/sshs.sh)"

```


* **🇨🇳 国内服务器**：
```bash
bash -c "$(curl -fsSL https://gitee.com/LeiD215/LeiD215.gitee.io/raw/master/tools/sshs/sshs.sh || wget -qO- https://gitee.com/LeiD215/LeiD215.gitee.io/raw/master/tools/sshs/sshs.sh)"

```


### 2. 带环境诊断版（推荐写入企业知识库/排查手册）

提供 Shell 兼容的 `printf` 格式，在下载遭遇环境故障时输出精准的排查建议：

```bash
(command -v curl >/dev/null 2>&1 && curl -fsSL "https://raw.githubusercontent.com/LeiD215/LeiD215.github.io/master/tools/sshs/sshs.sh" -o sshs.sh || wget -q "https://raw.githubusercontent.com/LeiD215/LeiD215.github.io/master/tools/sshs/sshs.sh" -O sshs.sh) && [ -s sshs.sh ] && chmod +x sshs.sh && sudo ./sshs.sh || printf "\n\033[31m[-] 安装失败！\033[0m\n\n常见原因：\n  • SSL 证书验证失败 → 同步时间: ntpdate pool.ntp.org 或 chronyc makestep\n  • GitHub 访问受限   → 请检查网络路由与 DNS 状态\n  • 缺少基本下载工具 → 安装: apt install curl 或 yum install wget\n\n"

```


* **🇨🇳 国内服务器**：
```bash
(command -v curl >/dev/null 2>&1 && curl -fsSL "https://gitee.com/LeiD215/LeiD215.gitee.io/raw/master/tools/sshs/sshs.sh" -o sshs.sh || wget -q "https://gitee.com/LeiD215/LeiD215.gitee.io/raw/master/tools/sshs/sshs.sh" -O sshs.sh) && [ -s sshs.sh ] && chmod +x sshs.sh && sudo ./sshs.sh || printf "\n\033[31m[-] 安装失败！\033[0m\n\n常见原因：\n  • SSL 证书验证失败 → 同步时间: ntpdate pool.ntp.org 或 chronyc makestep\n  • Gitee 访问受阻    → 请检查本地网络或 DNS 状态\n  • 缺少基本下载工具 → 安装: apt install curl 或 yum install wget\n\n"

```


---

## ⚠️ 生产加固安全验证流程

服务在重启后**当前连接不会断开**。为保证绝对安全，请严格按以下步骤操作：

1. **切勿关闭当前正在执行脚本的窗口！**
2. 在本地电脑上**新开一个终端窗口**，运行登录指令：
```bash
ssh -p <新端口> root@<服务器IP>

```


3. **验证登录行为**：
* **未启用 2FA**：能够凭私钥直接登入。
* **已启用 2FA**：通过密钥验证后，控制台会提示 `Verification code:`，此时输入绑定的验证器（1Password、手机 Authenticator 等）生成的 6 位数字方可登入。


4. **确认状态**：
* **测试通过**：回到脚本窗口输入 `y`，加固流程圆满完成。
* **测试失败/被卡住**：回到脚本窗口输入 `n`。脚本将立即调用 `rollback_all` 函数恢复系统状态。



---

## 📁 备份文件清单

脚本自动在相关配置目录下生成带有时间戳和进程 PID 标识的只读备份：

* `/etc/ssh/sshd_config.pre_secure_v1.0.0_YYYYMMDD_HHMMSS_PID`
* `/etc/pam.d/sshd.pre_secure_v1.0.0_YYYYMMDD_HHMMSS_PID`
* `/etc/chrony/chrony.conf.pre_secure_v1.0.0_YYYYMMDD_HHMMSS_PID`（仅在启用 2FA 且存在 chrony 时生成）
