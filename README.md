# vps-toolbox
## ⚡ 极速一键安装与快捷指令

本仓库提供两大独立利器，请按需选择并在 VPS 终端（Root 用户）粘贴执行：

### 🛠️ 工具一：VPS Master Toolbox Pro 全能运维工具箱 (`vps-toolbox.sh`)
> **一键聚合 11 大模块**：FRP 内网穿透、Sing-box 权威生态、Acme.sh 证书、Caddy/NPM 反代、YABS 跑分、NextTrace 回程路由、原版 BBR、WARP 双栈、Docker 官方一键、万能短链中心等。

```bash  wget 方式 (支持 IPv4 / 纯 IPv6)
wget -qO /usr/local/bin/vps https://raw.githubusercontent.com/fengjunzi0404/singbox/main/vps-toolbox.sh && chmod +x /usr/local/bin/vps && /usr/local/bin/vps

# curl 方式：
curl -fsSL https://raw.githubusercontent.com/fengjunzi0404/singbox/main/vps-toolbox.sh -o /usr/local/bin/vps && chmod +x /usr/local/bin/vps && /usr/local/bin/vps
