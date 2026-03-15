# 快速安装脚本
## `LuoPoJunZi`魔改版
```bash
bash <(curl -s -L https://raw.githubusercontent.com/LuoPoJunZi/Sing-box-LPMG/main/install.sh)
```
```bash
bash <(curl -s -L https://github.com/LuoPoJunZi/Sing-box-LPMG/raw/main/install.sh)
```
## `233boy`大佬的sing-box
```bash
bash <(wget -qO- -o- https://github.com/233boy/sing-box/raw/main/install.sh)
```

# 我的脚本卸载不掉怎么办？

不要紧，既然脚本自己动不了手，我们就直接用 Linux 原生命令进行**“物理超度”**，手动把它的所有残留连根拔起。

请直接复制以下这段完整的命令，一次性粘贴到终端并回车。它会帮你停止服务、清理定时任务、删除所有文件和快捷指令：

```bash
# 1. 停止并禁用相关服务
systemctl stop sing-box caddy 2>/dev/null
systemctl disable sing-box caddy 2>/dev/null

# 2. 删除 Sing-box 和可能存在的 CFtunnel 守护服务文件
rm -f /lib/systemd/system/sing-box.service
rm -f /lib/systemd/system/cftunnel-*.service
systemctl daemon-reload

# 3. 清理自动更新和日志清理的定时任务
crontab -l 2>/dev/null | grep -v -E "sing-box update|/var/log/sing-box" | crontab -

# 4. 删除所有核心文件、配置目录和日志
rm -rf /etc/sing-box /var/log/sing-box /usr/local/bin/sing-box /usr/local/bin/sb

# 5. 清理环境变量中的快捷命令别名并使其生效
sed -i "/sing-box/d" /root/.bashrc
sed -i "/alias sb=/d" /root/.bashrc
source /root/.bashrc

echo -e "\n✅ 物理清理完成！系统已恢复纯净状态。"

```

执行完这段代码后，你的服务器上就不会再有任何这个半成品的痕迹了。

### 下一步

当你看到 `✅ 物理清理完成！` 的提示后，你可以放心地重新运行你更新好的官方安装指令，重新部署完美版：

```bash
bash <(curl -s -L https://github.com/LuoPoJunZi/Sing-box-LPMG/raw/main/install.sh)

```



---

# Sing-box-LPMG 一键脚本完整使用文档

**Sing-box-LPMG** 是一款专为 Linux 服务器设计的 sing-box 一键安装管理脚本。它基于 [233boy](https://github.com/233boy/sing-box) 项目的核心逻辑进行深度重构，旨在提供**更美观的视觉体验、更智能的自动化运维以及更严谨的隐私保护**。

---

## 一、 脚本特性

### 1. 全面的协议支持

支持目前市面上主流的所有高性能协议：

* **基础类**：Shadowsocks (SS), Trojan, Hysteria2, TUIC。
* **隧道类**：VMess/VLESS (支持 WebSocket, HTTP2, gRPC, HTTPUpgrade)。
* **抗封锁类**：VLESS-REALITY (Vision), VLESS-HTTP2-REALITY。

### 2. LPMG 魔改版独有优化

* **现代面板 TUI**：全新的 UI 布局，操作逻辑更清晰，支持防误触退出。
* **分类协议选择**：将 20+ 种协议划分为“基础、隧道、抗封锁”三大区块，新手选型不再迷茫。
* **智能防火墙联动**：全自动识别并配置 `UFW` / `Firewalld` / `Iptables`，告别“节点建好连不上”的困扰。
* **隐私备注系统**：
* 允许在创建时自定义节点备注（如：`LUOPO`）。
* URL 链接中的备注部分彻底移除 IP 信息，分享更安全。


* **文件名重构**：配置文件以 `协议-备注-端口.json` 命名，管理极度直观。
* **一键查看总览**：支持快速列出服务器上所有节点的简明信息与链接。
* **自动运维**：预设 Cron 任务，实现每周一凌晨自动更新核心、每天凌晨自动清理日志释放磁盘空间。

---

## 二、 安装与卸载

### 1. 系统要求

* **操作系统**：Ubuntu 20.04+ / Debian 11+ / CentOS 7+。
* **架构**：x86_64 (amd64) 或 ARM64。
* **用户**：必须以 `root` 用户身份运行。

### 2. 安装/重装命令

```bash
bash <(curl -s -L https://raw.githubusercontent.com/LuoPoJunZi/Sing-box-LPMG/main/install.sh)

```

*安装过程中会引导你创建一个初始的 VLESS-REALITY 节点，并提示输入备注名。*

### 3. 完全卸载

进入脚本面板选择 `7`，或执行：

```bash
sb uninstall

```

---

## 三、 快速上手指南

### 1. 进入主面板

在终端输入以下命令即可进入管理界面：

```bash
sb

```

或使用原版命令：`sing-box`

### 2. 添加新配置

1. 在面板输入 `1` 进入添加界面。
2. 按照分类选择你中意的协议（推荐选择 **18. VLESS-REALITY**）。
3. 脚本会自动为你分配 20000 以上的随机端口并放行防火墙。
4. **输入自定义备注**：例如输入 `香港落地`。
5. 脚本将自动打印出该节点的详细参数和连接链接（URL）。

### 3. 查看节点信息

* **查看单个节点**：面板输入 `3`，根据列表选择对应的 `.json` 文件。
* **一键查看所有节点**：面板输入 `9` -> `1`。屏幕会清空并整齐列出服务器上所有正在运行的节点 URL。

### 4. 更改节点配置

面板输入 `2`。你可以针对某个节点单独修改以下内容：

* 更改端口（输入 `auto` 可再次随机分配）。
* 更改密码 / UUID。
* 更改伪装域名（SNI）或 REALITY 密钥对。

---

## 四、 进阶管理命令

如果您不想通过菜单点选，可以直接在命令行附加参数执行：

| 命令 | 说明 |
| --- | --- |
| `sb add` | 添加节点 |
| `sb del` | 删除节点 |
| `sb info` | 查看节点信息 |
| `sb all` | **[魔改]** 查看所有节点总览 |
| `sb status` | 查看 sing-box 运行状态 |
| `sb start` | 启动服务 |
| `sb stop` | 停止服务 |
| `sb restart` | 重启服务 |
| `sb cron` | **[魔改]** 配置自动更新与日志清理任务 |
| `sb update` | 手动更新脚本或核心 |
| `sb log` | 查看实时运行日志 |

---

## 五、 常见问题排查 (FAQ)

#### 1. 提示“✅ 防火墙已放行”，但客户端依然连不上？

* **检查厂商安全组**：脚本只能放行 VPS 内部系统防火墙。如果你使用的是**腾讯云、阿里云、甲骨文、AWS**等，必须登录其网页控制台，手动开放对应的端口（或者开启全端口）。
* **检查时间同步**：VMess/VLESS 协议要求服务器时间误差在 90 秒内。脚本已尝试开启 NTP，若失效请手动同步时间。

#### 2. 如何修改现有的节点备注？

* 由于备注与配置文件名和文件内部 Tag 深度绑定，目前最稳妥的方法是：先输入 `sb del` 删除该节点，然后重新输入 `sb add` 添加并设置新备注。

#### 3. 为什么 URL 里的 Address 还是显示我的 IP？

* 这是正常的。`Address` 必须是你的真实 IP（或解析好的域名），否则客户端无法寻址。LPMG 魔改版的隐私保护是指在 `#` 号后面的备注（Remark）部分去除了 IP，确保你截图或分享链接时不会一眼泄露地址。

---

## 六、 相关资源

* **GitHub 项目地址**：[LuoPoJunZi/Sing-box-LPMG](https://github.com/LuoPoJunZi/Sing-box-LPMG)
* **反馈问题**：请在 GitHub Issues 提交。

## 七、 233boy大佬的文档

安装及使用：https://233boy.com/sing-box/sing-box-script/

## 帮助

使用：`sing-box help`

```
sing-box script v1.0 by 233boy
Usage: sing-box [options]... [args]...

基本:
   v, version                                      显示当前版本
   ip                                              返回当前主机的 IP
   pbk                                             同等于 sing-box generate reality-keypair
   get-port                                        返回一个可用的端口
   ss2022                                          返回一个可用于 Shadowsocks 2022 的密码

一般:
   a, add [protocol] [args... | auto]              添加配置
   c, change [name] [option] [args... | auto]      更改配置
   d, del [name]                                   删除配置**
   i, info [name]                                  查看配置
   qr [name]                                       二维码信息
   url [name]                                      URL 信息
   log                                             查看日志
更改:
   full [name] [...]                               更改多个参数
   id [name] [uuid | auto]                         更改 UUID
   host [name] [domain]                            更改域名
   port [name] [port | auto]                       更改端口
   path [name] [path | auto]                       更改路径
   passwd [name] [password | auto]                 更改密码
   key [name] [Private key | atuo] [Public key]    更改密钥
   method [name] [method | auto]                   更改加密方式
   sni [name] [ ip | domain]                       更改 serverName
   new [name] [...]                                更改协议
   web [name] [domain]                             更改伪装网站

进阶:
   dns [...]                                       设置 DNS
   dd, ddel [name...]                              删除多个配置**
   fix [name]                                      修复一个配置
   fix-all                                         修复全部配置
   fix-caddyfile                                   修复 Caddyfile
   fix-config.json                                 修复 config.json
   import                                          导入 sing-box/v2ray 脚本配置

管理:
   un, uninstall                                   卸载
   u, update [core | sh | caddy] [ver]             更新
   U, update.sh                                    更新脚本
   s, status                                       运行状态
   start, stop, restart [caddy]                    启动, 停止, 重启
   t, test                                         测试运行
   reinstall                                       重装脚本

测试:
   debug [name]                                    显示一些 debug 信息, 仅供参考
   gen [...]                                       同等于 add, 但只显示 JSON 内容, 不创建文件, 测试使用
   no-auto-tls [...]                               同等于 add, 但禁止自动配置 TLS, 可用于 *TLS 相关协议
其他:
   bbr                                             启用 BBR, 如果支持
   bin [...]                                       运行 sing-box 命令, 例如: sing-box bin help
   [...] [...]                                     兼容绝大多数的 sing-box 命令, 例如: sing-box generate uuid
   h, help                                         显示此帮助界面

谨慎使用 del, ddel, 此选项会直接删除配置; 无需确认
文档(doc) https://233boy.com/sing-box/sing-box-script/
```