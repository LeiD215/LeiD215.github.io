# Swap自用版

`swapopt.sh` 是一款专为 Linux VPS 打造的**虚拟内存（Swap）自适应创建与内核策略锁定脚本**，100% 兼容 `sh` (dash) 引导，运行时绝无碎屑报错。

---

## 🚀 核心特性

* **无碎屑全兼容**：采用 POSIX sh 标准规范重构，用 `printf` 替代 `echo -e`，使用 `sh` 运行不会吐出 `-e` 文本。
* **智能冲突防御**：启动时自动扫描并清理系统已有的 `swappiness` 冲突配置，防止内核参数打架。
* **业务场景切换**：支持 **[1] 纯 Xray 节点** 与 **[2] 复合服务器 (Docker/Web/数据库)** 双策略一键锁定。
* **安全平滑降级**：首选 `fallocate` 瞬间分配；在不支持的虚拟化架构上自动降级为 `dd` 擦写，确保创建 100% 成功。
* **无痕一键卸载**：独立写入 `/etc/sysctl.d/99-dleia-swapopt.conf`，支持一键物理抹除，秒回原生状态。

---

## 💻 快速入门

脚本无需使用 `chmod +x` 提前赋权，直接使用 `sh` 引导即可。

### 1. 无人值守自动流 (批量/一键装机 🏆 推荐)

自动识别硬件，并按默认的“复合服务器场景”最优推荐值全自动秒刷完成：

```bash
wget https://github.com/LeiD215/LeiD215.github.io/raw/refs/heads/master/tools/Swap/swapopt.sh -O swap && sh swap 2G -y

```

### 2. 人工交互确认流 (精细化手动验证)

只指定容量运行，可手动选择业务场景并确认内核推荐值：

```bash
wget https://github.com/LeiD215/LeiD215.github.io/raw/refs/heads/master/tools/Swap/swapopt.sh -O swap && sh swap 2G

```

### 3. 一键无痕卸载流 (干净利落还原)

关闭并物理删除 Swap 文件，擦除开机挂载，拔除内核配置文件：

```bash
sh swap --uninstall

```

*(注：如果创建时指定了自定义路径，如 `sh swap 4G /mnt/swap`，则卸载时也需带上路径：`sh swap --uninstall /mnt/swap`)*

---

## 👑 黄金装机两步连招 (建议搭配 sysopt.sh)

为使系统底层加载达到完美协同，请遵循“先网络（95），后虚拟内存（99）”的原则：

```bash
# 第一步：解开系统网络连接数与 Systemd 高并发文件描述符上限
wget https://github.com/LeiD215/LeiD215.github.io/raw/refs/heads/master/tools/Sysopt/sysopt.sh -O sysopt.sh && sh sysopt.sh -y

# 第二步：挂载 2G 安全虚拟内存并锁定复合服务器防崩溃策略
wget https://github.com/LeiD215/LeiD215.github.io/raw/refs/heads/master/tools/Swap/swapopt.sh -O swap && sh swap 2G -y

```

> ⚠️ **运维注意**：两步全部跑完且自检通过后，请在终端输入 **`reboot`** 重启一次服务器。重启后，Systemd 的全局资源线程限制才会彻底刷新生效，整台 VPS 将稳如磐石！
