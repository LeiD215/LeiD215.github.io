# SSH Key Installer

[![LICENSE](https://img.shields.io/github/license/mashape/apistatus.svg?style=flat-square&label=LICENSE)](https://github.com/P3TERX/SSH_Key_Installer/blob/master/LICENSE)
[![GitHub Stars](https://img.shields.io/github/stars/P3TERX/SSH_Key_Installer.svg?style=flat-square&label=Stars)](https://github.com/P3TERX/SSH_Key_Installer/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/P3TERX/SSH_Key_Installer.svg?style=flat-square&label=Forks)](https://github.com/P3TERX/SSH_Key_Installer/fork)

Install SSH keys via GitHub, URL or local files

[Read the details in my blog (in Chinese) | 中文教程](https://p3terx.com/archives/ssh-key-installer.html)

## Usage

```
bash <(curl -fsSL git.io/key.sh) [options...] <arg>
```
```
bash <(curl -fsSL git.io/key.sh) [选项...] <参数>
```

## Options

* `-o` - Overwrite mode, this option is valid at the top
* `-g` - Get the public key from GitHub, the arguments is the GitHub ID
* `-u` - Get the public key from the URL, the arguments is the URL
* `-f` - Get the public key from the local file, the arguments is the local file path
* `-p` - Change SSH port, the arguments is port number
* `-d` - Disable password login

* `-o` - 覆盖模式，必须写在最前面才会生效
* `-g` - 从 GitHub 获取公钥，参数为 GitHub 用户名
* `-u` - 从 URL 获取公钥，参数为 URL
* `-f` - 从本地文件获取公钥，参数为本地文件路径
* `-p` - 修改 SSH 端口，参数为端口号
* `-d` - 禁用密码登录

## Lisence

[MIT](https://github.com/P3TERX/SSH_Key_Installer/blob/master/LICENSE) © P3TERX

## Other
```
mkdir -p ~/.ssh
curl -fsSL https://github.com/LeiD215/LeiD215.github.io/raw/master/tools/temp/gmail.key >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
sudo sed -i "s@.*\(PasswordAuthentication \).*@\1no@" /etc/ssh/sshd_config
sudo service sshd restart
```
