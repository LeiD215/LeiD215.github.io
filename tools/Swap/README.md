# Swap自用版

## Usage

First of all, download the main script:
```
wget https://raw.githubusercontent.com/LeiD215/LeiD215.github.io/master/tools/Swap/swap.sh -O swap && chmod +x swap
# or
curl https://raw.githubusercontent.com/LeiD215/LeiD215.github.io/master/tools/Swap/swap.sh -O swap && chmod +x swap
```

交互界面:
```
sh swap <size>
```

无人值守:
```
sh swap <size> -y
```

Example (with 4G):
交互模式：
```
sh swap 4G
```

全自动无人值守模式:
```
sh swap 4G -y
```

GEMINI搞出来的，记录一下，试试效果。

1. 核心参数配置从“死板固定”变为“智能场景推荐”
原脚本：
不考虑服务器的硬件高低，直接死板地往系统里写入 vm.swappiness = 10 和 vm.vfs_cache_pressure = 50。这在 1G/2G 的小内存 VPS 上遇到网络突发流量时，极易导致主服务（如 Xray）因内存窒息而被系统直接杀死（OOM）。

新脚本：
引入了智能推荐引擎。脚本启动后会自动读取服务器的物理内存，并结合用户选择的应用场景（纯 Xray 节点 vs 复合 Docker/Web 服务器）进行动态计算。

例如：遇到 1G 内存的 VPS，它会聪明地推荐 60 / 100 以确保服务器极限生存；遇到 8G 内存时，才推荐高性能的 10 / 60。

2. 系统内核配置路径更符合现代规范（不污染主配置）
原脚本：
使用 tee -a /etc/sysctl.conf 往系统的全局主配置文件尾部强行追加内容。这是一种比较粗暴的做法，多运行几次就会导致主文件充斥着重复的垃圾代码，且系统升级时容易被覆盖。

新脚本：
采用了现代 Linux（如 Debian 13/Ubuntu 24）推荐的模块化配置规范，将参数精准写入独立的 /etc/sysctl.d/99-swap-optimize.conf 文件。这种设计极度干净，不仅不会污染主系统，而且非常便于后续的统一管理、修改或删除。

3. 新增“全盘历史冲突检测与清理”功能（工业级防呆）
原脚本：
完全不检测系统过去的状况，不管不顾地直接去写新值。如果服务器之前被别的脚本或者你手动改过这些参数，多处配置重叠会导致内核加载时产生混乱。

新脚本：
具备配置审计功能。它会先扫描 /etc/sysctl.conf 和 /etc/sysctl.d/ 下的所有文件：

如果发现有历史冲突行，它会清晰地打印出冲突文件路径和当前的内核实时生效值。

在交互模式下会礼貌地询问你是否覆盖；一旦你确认，它会自动对旧文件进行 .bak 备份，然后用 sed 干净地剔除掉旧冲突行，确保新内核参数 100% 完美生效。

4. 彻底解决多发行版、老旧系统的“跨时代兼容性”
原脚本：

依赖 fallocate 命令创建文件。在部分特殊的虚拟化架构（如部分 OpenVZ / Btrfs 文件系统）下会直接闪退报错 swapfile has holes。

如果未来改用 free -m 抓取内存，在 CentOS 5/6 等老系统的不同格式下，命令可能会抓空导致脚本报错。

新脚本：

命令双保险降级机制：优先使用瞬间完成的 fallocate，一旦系统不支持，会自动无缝降级为最稳妥、兼容性 100% 的 dd 擦写命令。

硬核内存读取：摒弃了格式总在变的老旧 free 命令，直接读取 Linux 二十年来从未变过格式的底层 /proc/meminfo，从而让脚本从 CentOS 5 到 Debian 13 甚至未来的新发行版都能 100% 完美运行。

老系统补丁：自动判断并支持在缺少 /etc/sysctl.d/ 文件夹的极老 Linux 系统上自动补票创建。

5. 从单向脚本升级为“多模态运维工具”
原脚本：
只有一个功能：只能用来新建默认路径的 Swap，且必须进行人机交互。

新脚本：
重构为了支持多种语境的运维小工具：

自动化/无人值守模式：支持追加 -y 或 --auto 参数。在批量部署或写进自动化装机脚本时，它会保持沉默，全自动按推荐值搞定一切。

一键安全卸载模式：支持运行 ./swap.sh --uninstall。它不仅会帮你安全地关闭并删除 swap 文件，还会干净地抹掉 /etc/fstab 里的开机挂载项，并顺手拔掉 /etc/sysctl.d/ 里的参数文件，让系统秒回最纯净的初始状态。

完美的参数容错解析：不再死板限制输入顺序，它能自己用 case 语法从你输入的参数里盲猜哪个是大小（如 2G）、哪个是路径（如 /myswap），且完美兼容你最习惯的 sh swap 2G 运行指令。


# Swap

Simple swap setup script for Linux

Swap is an area on a hard drive that has been designated as a place where the operating system can temporarily store data that it can no longer hold in RAM.

Disclamer: This script may not work on every GNU/Linux distro. Sorry.

## Usage

First of all, download the main script:
```
wget https://raw.githubusercontent.com/Cretezy/Swap/master/swap.sh -O swap
# or
curl https://raw.githubusercontent.com/Cretezy/Swap/master/swap.sh -o swap
```

Then simply run the file with this format:
```
sh swap <size>
```

Example (with 4G):
```
sh swap 4G
```

The default path for the swap file is /swapfile. If you wish to change this, simple the file location (file must not exist) add it to the command:
```
sh swap 4G /swap
```
