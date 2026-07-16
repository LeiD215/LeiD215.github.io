# sshs.sh (v1.0.0)

`sshs.sh` 是一个用于 Linux 服务器 SSH 安全加固的一键脚本。支持修改端口、导入公钥、禁用密码登录，并可选择性配置基于 TOTP（如 Google Authenticator、1Password）的双因子认证（2FA）。

---

## 核心功能

* **基础安全加固**：
* 修改默认 SSH 端口（支持占用检测与安全范围校验）。
* 强制关闭密码登录，仅允许 Root 用户通过密钥登录。
* 自动导入指定公钥（支持从 GitHub / Gitee 动态下载并进行指纹合规校验）。


* **双因子认证 (2FA)**（可选）：
* 自动安装 `google-authenticator` PAM 模块。
* 精准配置 PAM 认证栈首行，防绕过。
* 强制声明 `AuthenticationMethods publickey,keyboard-interactive`（必须同时通过密钥和验证码）。


* **配套安全支撑**：
* **时间同步**：配置 Apple、阿里、腾讯、Cloudflare 高可用 NTP 服务（2FA 强制要求时间精准）。
* **防火墙适配**：自动清理旧端口并放行新端口，兼容 UFW、Firewalld、iptables。
* **SELinux 兼容**：自动识别端口占用类型，防端口策略冲突。


* **高鲁棒性与防锁死**：
* 脚本启动时定格备份时间戳（引入 PID 规避多机并发命名冲突）。
* 重启 SSH 服务前，物理校验 `pam_google_authenticator.so` 是否在磁盘中真实存在。
* 验证失败或用户人工测试连接不通时，自动一键无残留回滚（复原配置并删除临时 2FA 令牌）。



---

## 兼容性说明

脚本已在以下系统通过测试：

* **Debian 系**：Debian 10/11/12、Ubuntu 20.04/22.04/24.04
* **红帽/企业系**：CentOS 7/8/9、Rocky Linux 8/9、AlmaLinux 8/9
* **定制系统**：Amazon Linux（兼容非标 PAM 配置路径）

---

## 使用方法

### 1. 下载并运行

在目标服务器执行以下命令：

```bash
# 下载脚本
nano sshs.sh  # 粘贴脚本代码并保存

# 赋予执行权限
chmod +x sshs.sh

# 以 root 权限运行
sudo ./sshs.sh

```

### 2. 交互配置流程

脚本执行后将进行以下交互引导：

1. **选择公钥源**：选择国内（Gitee）或国外（GitHub）下载指定的公钥。
2. **输入新端口**：输入 1024-65535 之间的非占用数字端口（默认 2222）。
3. **启用 2FA**：若选择启用（输入 `y`），脚本将自动配置 NTP、安装 PAM 模块并输出二维码与 5 个 8 位数的应急备用码（Scratch codes）。

---

## ⚠️ 生产测试与防锁死操作指南（关键）

配置完成后，脚本会重新启动 SSH 服务，但**不会断开当前连接**。请严格按照以下步骤验证：

1. **绝对不要关闭当前运行脚本的终端窗口**。
2. 在本地电脑新开一个终端窗口，执行以下命令尝试登录：
```bash
ssh -p <新端口> root@<服务器IP>

```


3. **验证登录行为**：
* 若**未开启 2FA**：应当能通过私钥免密直接登入。
* 若**已开启 2FA**：通过密钥校验后，终端应提示 `Verification code:`，此时输入手机 App 或 1Password 上的 6 位动态数字。


4. **决策确认**：
* **测试登录成功**：回到脚本终端，输入 `y`，完成加固并退出。
* **登录失败/被拦截**：回到脚本终端，输入 `n`。脚本会立即启动**无残留回滚**，将 SSH 配置、PAM 栈、时间同步复原，并删掉临时 2FA 文件，恢复到加固前的状态。



---

## 备份文件说明

脚本修改的所有关键系统文件均在同目录下留有备份，格式为：

* `/etc/ssh/sshd_config.pre_secure_v1.0.0_YYYYMMDD_HHMMSS_PID`
* `/etc/pam.d/sshd.pre_secure_v1.0.0_YYYYMMDD_HHMMSS_PID`
* `/etc/chrony/chrony.conf.pre_secure_v1.0.0_YYYYMMDD_HHMMSS_PID`
