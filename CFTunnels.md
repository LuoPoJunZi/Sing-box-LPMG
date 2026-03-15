# 🚀 终极指南：使用 Cloudflare Tunnels 结合 Sing-box 实现无公网 IP 内网穿透

在科学上网和节点搭建的过程中，没有公网 IP、服务器被墙、或者端口被深度阻断是极其常见的问题。(AI写的教程，见谅)

**Cloudflare Tunnel (CFtunnel)** 是解决这一痛点的终极武器。它能让你的本地服务主动与 Cloudflare 边缘节点建立安全加密隧道，无需开放任何公网端口，即可通过 Cloudflare 的 CDN 网络将流量安全转发出来。

配合 **Sing-box-LPMG** 魔改脚本，你可以实现一键全自动部署。以下是完整的保姆级图文教程。

---

## 🛠️ 课前准备

1. 一个 **Cloudflare 账号**，并且已经在 CF 托管了一个属于你的域名（例如 `example.com`）。
2. 一台安装了 Linux (Debian/Ubuntu 推荐) 的 VPS，并已成功安装 [Sing-box-LPMG 一键脚本](https://github.com/LuoPoJunZi/Sing-box-LPMG)。

---

## 🟢 第一阶段：初始化 Zero Trust 控制台 (首次使用必看)

如果你是第一次使用 Cloudflare 的高级安全功能，你需要先激活 Zero Trust 专属面板。

1. 登录 Cloudflare 主页，在左侧菜单栏找到并点击 **Zero Trust**。
2. 如果界面显示 **"Welcome to Cloudflare Zero Trust"**，请点击蓝色的 **Get started (开始使用)** 按钮。
3. 按照向导提示，设置一个团队名称（Team domain），随意输入英文字母即可。
4. **⚠️ 重点避坑：** 在选择订阅计划时，**务必选择 Free (免费版)**。
5. 系统会强制要求绑定一种支付方式（信用卡或 PayPal）以防止滥用。**请放心绑定，免费计划绝对不会产生任何扣费。**
6. 绑定成功后，即可进入真正的 Zero Trust 专属控制台。

---

## 🟡 第二阶段：创建隧道并提取核心 Token

在这个专属的控制台中，我们将创建一条专属隧道，并获取脚本部署所需的核心凭证（Token）。

1. 在 Zero Trust 左侧菜单栏，依次点击 **网络 (Networks) -> Tunnels (隧道)**。
2. 点击蓝色的 **Add a tunnel (创建隧道)** 按钮。
3. **选择隧道类型**：页面会提供两个选项，**必须点击左侧的 "Cloudflared (推荐)"**，切勿选择右侧的 WARP。
4. **命名隧道**：随意填写一个好记的名字（如 `LPMG-Node`），点击下一步/保存。
5. **选择操作系统**：在环境选择页面，点击 **Debian** 或 **Ubuntu**。
6. **🔑 提取通关密码 (Token)**：
* 在页面下方会生成一个黑色的代码框，包含类似 `sudo cloudflared service install eyJh...` 的安装命令。
* **千万不要复制整行！** 仔细定位，双击选中最后面那串**以 `ey` 开头的超长无规律字符**，并将其复制。
* 这串乱码就是极其重要的 **Tunnel Token**，请妥善保管。



---

## 🟠 第三阶段：在 VPS 终端一键部署节点

拿到 Token 后，剩下的脏活累活全部交给脚本自动完成。

1. SSH 登录你的 Linux 服务器，输入命令 `sb` 唤出 Sing-box-LPMG 魔改管理面板。
2. 输入 `1` 选择 **[添加配置]**。
3. 在协议列表中，找到 **[隧道穿透]** 区块，输入对应的序号（如 `21` 选择 CFtunnel）。
4. **分配端口**：提示输入端口时，**直接敲回车**，脚本会为你自动分配一个 20000 以上的空闲内部端口。
5. **输入 Token**：根据提示，将你在第二阶段复制的 **Tunnel Token** 粘贴进去并回车。
6. **填写备注**：为节点起一个自定义备注（例如 `LUOPOMG`）。
7. **🔔 牢记端口号**：屏幕会打印绿色成功提示，并显示 **“✅ CFtunnel 穿透守护服务 (关联内部端口: 61505) 已创建”**。请务必记住这个五位数的端口号（本文以 `61505` 为例）。

---

## 🔴 第四阶段：配置公网域名路由 (打通任督二脉)

节点已经在 VPS 内部跑起来了，现在我们需要告诉 Cloudflare，把哪个域名的流量转发给这个内部端口。

1. 回到刚才的 Cloudflare 网页端，点击右下角的 **下一步 (Next / 路由隧道)**。
2. 在 **Public Hostnames (公共主机名)** 页面，进行如下关键配置：
* **Subdomain (子域名)**：随意填写前缀（如 `www`, `node1`, `vless`）。也可留空直接使用主域名。
* **域 (Domain)**：下拉选择你在 CF 托管的域名（如 `example.com`）。
* **Path (路径)**：**保持完全空白，什么都不要填！**


3. 在下方的 **服务 (Service)** 区块配置内部映射：
* **类型 (Type)**：下拉选择 **`HTTP`**。（注意：即便跑的是 WS 流量，这里也必须选 HTTP）。
* **URL**：填写 `127.0.0.1:你的端口号` 或 `localhost:你的端口号`。（例如：**`127.0.0.1:61505`**）。


4. 点击右下角的蓝色按钮 **完成设置 (Save hostname)**。

---

## 🚀 最终阶段：组合链接，完美起飞

你的终端脚本在部署完成后，会吐出一条包含模板字符的原始 VLESS 链接，类似这样：

> `vless://f917...2cc6a@你的CF绑定域名(需修改):443?encryption=none&security=tls&type=ws&host=你的CF绑定域名(需修改)&path=/f917...2cc6a#LUOPOMG`

**最后的组装：**
将链接中的 `你的CF绑定域名(需修改)` 替换为你在第四阶段配置的完整域名（例如 `www.example.com`）。

**成品示例：**

> `vless://f917...2cc6a@www.example.com:443?encryption=none&security=tls&type=ws&host=www.example.com&path=/f917...2cc6a#LUOPOMG`

**使用方法：**
复制这串完整的链接，导入到 v2rayN、v2rayNG、Clash Verge 等支持 VLESS 协议的客户端中，即可畅享完全隐匿、抗封锁的安全网络体验！

---
