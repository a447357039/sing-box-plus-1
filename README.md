# 🚀 Sing-Box-Plus

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**一键部署 20 节点多协议代理服务的 Bash 管理脚本**，基于 [sing-box](https://github.com/SagerNet/sing-box) 核心。

---

## ✨ 功能亮点

| 类别 | 详情 |
|------|------|
| **20 节点** | 10 直连 + 10 WARP 出口，每种协议各一个，互不冲突 |
| **10 种协议** | VLESS Reality · VLESS gRPC Reality · Trojan Reality · Hysteria2 · VMess WS · Hysteria2 obfs · SS2022 · Shadowsocks · TUIC v5 · AnyTLS |
| **WARP 出口** | Cloudflare WARP 线路，解锁 Netflix / Disney+ 等流媒体更友好 |
| **DNS 故障切换** | Cloudflare DoH → Google DoH → UDP 1.0.0.1，systemd timer 定期检测并自动切换 |
| **自定义路由** | 按域名 / geosite 规则指定 WARP、本机 IPv4/IPv6、或导入的远程 VPS 出口 |
| **TLS 证书** | 自签证书 / 手动上传公开有效证书 / ACME 自动申请续期，三种模式一键切换 |
| **连接稳定** | TCP keepalive · 可调 UDP timeout · WARP 保活 · 全参数环境变量覆盖 |
| **运维友好** | 一键网络诊断 · 端口轮换 · BBR 加速 · 服务重启/DNS 切换日志持久化 |
| **多发行版** | Debian / Ubuntu · CentOS / RHEL · Arch · openSUSE · 包管理器优先 + 二进制回退 |

---

## 📋 系统要求

- Linux VPS（推荐 Debian 11+ / Ubuntu 20.04+）
- Root 权限
- 20 个可用端口（脚本自动随机分配并配置防火墙）

---

## 🚀 快速开始

方法一：wget（推荐）

```bash
wget -O sbp.sh https://raw.githubusercontent.com/yayitinyu/sing-box-plus/main/sing-box-plus.sh && bash sbp.sh
```

方法二：curl

```bash
curl -fsSL -o sbp.sh https://raw.githubusercontent.com/yayitinyu/sing-box-plus/main/sing-box-plus.sh && bash sbp.sh
```

> ⚠️ 本脚本为**交互式菜单**，不支持 `curl | bash` 管道方式运行。

---

## 📖 菜单功能

```
═══════════════════════════════════════════════
 🚀 Sing-Box-Plus 管理脚本 🚀
═══════════════════════════════════════════════
  1) 安装/部署（20 节点）
  2) 查看分享链接
  3) 重启服务
  4) 一键更换所有端口
  5) 一键开启 BBR
  6) 更新 sing-box 版本
  7) 一键网络诊断
  8) 自定义路由配置
  9) 卸载
  0) 退出
═══════════════════════════════════════════════
```

---

## 🔐 TLS 证书模式

部署时为 **Hysteria2 / TUIC / AnyTLS** 选择以下模式之一：

### 1. 自签证书（默认）

- 无需域名，开箱即用
- 分享链接自动附带 `insecure=1&allowInsecure=1`
- 客户端需允许不安全连接

### 2. 手动上传证书

- 将公开 CA 签发的 `fullchain.pem` 和未加密私钥上传到服务器
- 输入证书域名和两个文件的绝对路径
- 脚本自动验证：有效期、域名匹配、证书链完整性、公私钥配对
- **SNI 自动与域名保持一致**，避免域名不匹配报错

### 3. ACME 自动申请

- 输入已解析到服务器公网 IP 的域名（需 DNS only，关闭 CDN 代理）
- 使用 sing-box 内置 ACME 向 Let's Encrypt 申请证书并自动续期
- 优先使用 TCP 80 端口 HTTP-01 验证；若 80 被占用，回退到 TCP 443 TLS-ALPN-01

> 💡 手动证书或 ACME 模式启用后，Hysteria2 / TUIC / AnyTLS 的分享链接会改用证书域名，SNI 与服务端配置严格一致。VLESS Reality、Trojan Reality、VMess WS 和 Shadowsocks 节点不受此设置影响。
>
> 如需切换证书模式，重新运行 `1) 安装/部署` 即可，已有凭证和端口会保留。

---

## 🌐 节点说明

### 直连节点（10 个）

通过服务器本机 IP 直接出口访问互联网。

### WARP 节点（10 个，带 `-warp` 后缀）

流量经由 Cloudflare WARP 出口，适用于：

- 解锁 Netflix、Disney+、ChatGPT 等受地域限制的服务
- 规避服务器 IP 被目标网站封锁

### 自定义路由

菜单 `8) 自定义路由配置` 可按目标网站指定出口：

| 出口类型 | 用途示例 |
|----------|----------|
| 本机 WARP | `geosite:netflix` 走 WARP 解锁流媒体 |
| 本机 IPv4 | `suffix:openai.com` 固定走 IPv4 出口 |
| 本机 IPv6 | 需要原生 IPv6 的场景 |
| 远程 VPS 节点 | 粘贴分享链接或 sing-box outbound JSON 导入 |

匹配项支持逗号或空格分隔，支持以下格式：

```text
geosite:netflix, suffix:openai.com, domain:example.com, keyword:google, regex:.*\.example\.org$
```

简写规则：
- `netflix` → 按 `geosite:netflix` 处理
- `example.com` → 按 `suffix:example.com` 处理

---

## 📂 文件结构

| 文件 | 路径 | 说明 |
|------|------|------|
| 主配置 | `/opt/sing-box/config.json` | sing-box 运行配置 |
| 环境配置 | `/opt/sing-box/env.conf` | 运行参数与功能开关 |
| 凭证信息 | `/opt/sing-box/creds.env` | UUID、密码、密钥 |
| 端口信息 | `/opt/sing-box/ports.env` | 20 个端口分配 |
| WARP 配置 | `/opt/sing-box/warp.env` | WireGuard 密钥与端点 |
| 自定义路由 | `/opt/sing-box/routes.json` | 用户自定义路由规则 |
| 证书目录 | `/opt/sing-box/cert/` | TLS 证书与私钥 |
| 重启记录 | `/opt/sing-box/restart.log` | 服务启停日志 |
| DNS 切换记录 | `/opt/sing-box/dns-health.log` | DNS 上游切换日志 |
| 诊断报告 | `/opt/sing-box/diagnostics/` | 网络诊断快照 |

---

## ⚙️ 环境变量

可在运行脚本前通过环境变量自定义行为：

```bash
# 指定 sing-box 版本（推荐 1.13+）
SINGBOX_TAG=v1.13.13 bash sbp.sh

# 跳过启动依赖检查
SBP_SKIP_DEPS=1 bash sbp.sh

# 强制二进制模式（跳过包管理器）
SBP_BIN_ONLY=1 bash sbp.sh

# 调整连接参数
UDP_TIMEOUT=15m TCP_KEEP_ALIVE=30s TCP_KEEP_ALIVE_INTERVAL=30s \
WARP_KEEPALIVE_INTERVAL=25 DNS_HEALTH_INTERVAL=2m bash sbp.sh
```

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `SINGBOX_TAG` | `latest` | sing-box 发行版本号 |
| `SBP_SKIP_DEPS` | `0` | 设为 `1` 跳过启动时依赖检查 |
| `SBP_BIN_ONLY` | `0` | 设为 `1` 强制走二进制下载 |
| `SBP_SOFT` | `0` | 设为 `1` 宽松模式（依赖安装失败时继续） |
| `TCP_KEEP_ALIVE` | `30s` | TCP 保活时间 |
| `TCP_KEEP_ALIVE_INTERVAL` | `30s` | TCP 保活探测间隔 |
| `UDP_TIMEOUT` | `10m` | UDP NAT 过期时间 |
| `WARP_KEEPALIVE_INTERVAL` | `25` | WARP WireGuard 保活间隔（秒） |
| `DNS_HEALTH_INTERVAL` | `2m` | DNS 健康检查周期 |

网络参数会持久保存到 `/opt/sing-box/env.conf`。

---

## 📱 客户端导入

安装完成后输出 20 个分享链接，可直接导入以下客户端：

- **v2rayN** / **v2rayNG**
- **Clash Meta** / **Mihomo**
- **NekoBox** / **sing-box 客户端**
- **Shadowrocket** / **Quantumult X**

> 💡 AnyTLS 使用 `h2` / `http/1.1` ALPN，分享链接附带 `fp=chrome`。部分客户端可能不支持直接导入 AnyTLS 链接，可按输出的服务器、端口、SNI、ALPN 和密码手动添加。

---

## 🔧 常见问题

<details>
<summary><b>Hysteria2 / TUIC / AnyTLS 报域名不匹配错误？</b></summary>

确认证书模式和 SNI 一致：
- **自签证书**：客户端需勾选「允许不安全连接」
- **手动证书 / ACME**：确保域名 A 记录指向服务器 IP，脚本会自动将 SNI 设为与证书域名一致

如已部署但仍报错，重新运行 `1) 安装/部署` 并重新配置证书即可。
</details>

<details>
<summary><b>如何更换端口？</b></summary>

运行脚本选择 `4) 一键更换所有端口`，脚本会重新随机分配 20 个不重复端口、更新配置、放行防火墙并重启服务。
</details>

<details>
<summary><b>WARP 注册失败？</b></summary>

部分 IP 段可能被 Cloudflare 限制注册 WARP。脚本会自动禁用 WARP 节点，直连 10 个节点仍可正常使用。
</details>

<details>
<summary><b>ACME 证书申请失败？</b></summary>

- 确认域名 A 记录已指向服务器公网 IP（DNS only，关闭 CDN 代理）
- 确认 TCP 80 或 443 端口未被其他程序占用
- 云平台安全组中需手动放行对应端口
</details>

---

## 🙏 致谢

- [sing-box](https://github.com/SagerNet/sing-box) — 核心代理引擎
- [wgcf](https://github.com/ViRb3/wgcf) — WARP 账户注册工具
- 原作者 Alvin9999

---

## 📄 许可证

[MIT License](LICENSE)
