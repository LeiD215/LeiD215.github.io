#自用网络优化脚本

# 🛠️ sysopt.sh 使用说明书

sysopt.sh 是一款专门为 Linux 虚拟服务器（VPS）打造的系统级网络与资源限制自适应优化脚本。

🎯 适用场景
高级翻墙/代理节点：优化 TCP 核心缓冲区与连接队列，大幅压榨网络带宽，显著降低高并发下的网络延迟抖动（Bufferbloat）。

多节点管理程序 (如 Remnawave Panel)：自动开启透明大页（THP）加速，大幅提升节点间频繁加解密与通信时的 CPU 寻址性能。

复合业务服务器：完美放开 Systemd 与系统的文件描述符限制，防止 Docker 容器、Web 服务器（Nginx）以及数据库（MySQL/MariaDB）在高并发下报 Too many open files 错误。

🐧 兼容系统
脚本基于标准 POSIX sh 规范重构，100% 兼容以下系统，绝无语法碎屑报错：

Debian 9 / 10 / 11 / 12 / 13 (最新版)

Ubuntu 18.04 / 20.04 / 22.04 / 24.04

CentOS / Rocky Linux / AlmaLinux 7 / 8 / 9
---

## 🚀 核心特性

* **智能自适应**：自动识别 VPS 内存与 CPU，动态划分优化等级，拒绝一刀切。
* **混合安全线**：针对小内存机型死守缓冲区边界，保障 Docker 与数据库不爆 RAM。
* **不污染系统**：优化参数独立写入 `/etc/sysctl.d/95-dleia-sysopt.conf`，可一键无痕卸载。
* **全 sh 兼容**：基于 POSIX sh 规范重构，在 Debian 13 等新旧系统上直接用 `sh` 运行绝无碎屑报错。

---

## 💻 快速入门

脚本无需提前使用 `chmod +x` 赋权，直接使用 `sh` 引导即可。

### 1. 无人值守流 (批量/一键装机 🏆 推荐)

自动识别硬件并按推荐值全自动秒刷完成：

```bash
wget https://github.com/LeiD215/LeiD215.github.io/raw/refs/heads/master/tools/Sysopt/sysopt.sh -O sysopt.sh && sh sysopt.sh -y

```

### 2. 人工交互流 (手动验证)

运行后会展示为您量身定制的硬件策略，需手动输入 `y` 确认：

```bash
wget https://github.com/LeiD215/LeiD215.github.io/raw/refs/heads/master/tools/Sysopt/sysopt.sh -O sysopt.sh && sh sysopt.sh

```

### 3. 一键卸载流 (无痕还原)

彻底撤销所有内核与系统资源限制优化，秒回官方原生状态：

```bash
sh sysopt.sh --uninstall

```

---

## 👑 黄金装机两步连招 (建议搭配 swapopt.sh)

为使系统底层加载达到完美协同，请遵循“先网络（95），后虚拟内存（99）”的原则：

```bash
# 第一步：解开系统网络与高并发资源限制
wget https://github.com/LeiD215/LeiD215.github.io/raw/refs/heads/master/tools/Sysopt/sysopt.sh -O sysopt.sh && sh sysopt.sh -y

# 第二步：挂载 2G 安全虚拟内存并锁定复合服务器策略
wget https://github.com/LeiD215/LeiD215.github.io/raw/refs/heads/master/tools/Swap/swapopt.sh -O swap && sh swap 2G

```

> ⚠️ **注意**：两步全部跑完且自检报告显示正常后，请在终端输入 **`reboot`** 重启一次服务器，Systemd 资源限制即可彻底刷新生效！
