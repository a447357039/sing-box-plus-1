# Sing-Box-Plus

一键部署 20 节点代理服务的 Bash 脚本，基于 [Sing-Box](https://github.com/SagerNet/sing-box) 核心。

## 功能特点

- **20 个代理节点**：10 个直连 + 10 个 WARP 出口（解锁流媒体更友好）
- **支持协议**：VLESS Reality、VLESS gRPC Reality、Trojan Reality、Hysteria2、VMess WS、Hysteria2 obfs、SS2022、SS、TUIC v5、AnyTLS
- **新版兼容**：配置生成已迁移到 sing-box 1.13+ 可用的 DNS 服务器格式和 WireGuard endpoint
- **连接稳定性**：TCP keepalive、可配置 UDP timeout、WARP 25 秒保活
- **DNS 故障切换**：Cloudflare DoH → Google DoH → UDP 备用 DNS
- **自定义路由**：按域名 / geosite 指定本机 WARP、本机 IPv4、本机 IPv6 或导入的远程 VPS 节点出口
- **运行诊断**：一键生成网络报告，并持久记录服务重启和 DNS 切换
- **证书可选**：支持自签证书、手动指定公开有效证书，以及 ACME 自动申请和续期
- **全自动化**：依赖安装、证书配置、防火墙配置、BBR 加速
- **多发行版支持**：Debian/Ubuntu、CentOS/RHEL、Arch、openSUSE

## 系统要求

- Linux VPS（推荐 Debian 11+ / Ubuntu 20.04+）
- Root 权限
- 开放 20 个随机端口（脚本自动配置防火墙）

## 快速开始

```bash
# 方法一：wget 下载后运行（推荐）
wget -O sbp.sh https://raw.githubusercontent.com/yayitinyu/sing-box-plus/main/sing-box-plus.sh
bash sbp.sh

# 方法二：curl 下载后运行
curl -fsSL -o sbp.sh https://raw.githubusercontent.com/yayitinyu/sing-box-plus/main/sing-box-plus.sh
bash sbp.sh
```

> ⚠️ **注意**：本脚本为交互式菜单，不支持 `curl | bash` 管道方式运行。

## 菜单选项

| 选项 | 功能 |
|------|------|
| 1 | 安装/部署（20 节点） |
| 2 | 查看分享链接 |
| 3 | 重启服务 |
| 4 | 一键更换所有端口 |
| 5 | 一键开启 BBR |
| 6 | 更新 sing-box 版本 |
| 7 | 一键网络诊断 |
| 8 | 自定义路由配置 |
| 9 | 卸载 |
| 0 | 退出 |

## 节点说明

### 直连节点（10 个）
直接通过服务器 IP 出口访问互联网。

### WARP 节点（10 个，带 `-warp` 后缀）
流量经由 Cloudflare WARP 出口，适用于：
- 解锁 Netflix、Disney+ 等流媒体
- 规避服务器 IP 被封锁

### 自定义路由

菜单 `8) 自定义路由配置` 可按目标网站指定出口：

- 本机 WARP：例如让 `geosite:netflix` 走 WARP
- 本机 IPv4 / IPv6：例如让 `suffix:openai.com` 固定走 IPv4 或 IPv6
- 导入远程 VPS 节点：可粘贴 sing-box outbound JSON，或本脚本生成的常见分享链接（VLESS、Trojan、Hysteria2、VMess、Shadowsocks、TUIC、AnyTLS）

匹配项支持逗号或空格分隔：

```text
geosite:netflix, suffix:openai.com, domain:example.com, keyword:google
```

简写规则：

- `netflix` 会按 `geosite:netflix` 处理
- `example.com` 会按 `suffix:example.com` 处理

## 配置文件位置

| 文件 | 路径 |
|------|------|
| 主配置 | `/opt/sing-box/config.json` |
| 凭证信息 | `/opt/sing-box/creds.env` |
| 端口信息 | `/opt/sing-box/ports.env` |
| WARP 配置 | `/opt/sing-box/warp.env` |
| 自定义路由 | `/opt/sing-box/routes.json` |
| 证书 | `/opt/sing-box/cert/` |
| 重启记录 | `/opt/sing-box/restart.log` |
| DNS 切换记录 | `/opt/sing-box/dns-health.log` |
| 网络诊断报告 | `/opt/sing-box/diagnostics/` |

## TLS 证书模式

部署时可为 Hysteria2、Hysteria2 obfs、TUIC 和 AnyTLS 选择以下模式：

1. **自签证书**：默认模式，分享链接使用服务器 IP，并包含 `insecure=1&allowInsecure=1`。
2. **手动证书**：先将公开 CA 签发的 `fullchain.pem` 和未加密私钥上传到服务器，再输入证书域名及两个文件的绝对路径。脚本会检查有效期、域名、证书链以及证书和私钥是否匹配。
3. **ACME 自动申请**：输入已解析到服务器公网 IP 的域名，脚本使用 sing-box 内置 ACME 向 Let's Encrypt 申请并自动续期。

手动证书或 ACME 模式启用后，上述协议的分享链接会改用证书域名，并移除 `insecure` / `allowInsecure`，恢复客户端证书验证。Reality、VMess 和 Shadowsocks 节点不受此设置影响。

> ACME 域名应使用 DNS only（关闭 CDN/反向代理），并确保 TCP 80 可用；若 80 已占用，脚本会尝试使用 TCP 443 的 TLS-ALPN 验证。云平台安全组中的对应端口仍需手动放行。

如需切换证书模式，重新运行 `1) 安装/部署` 即可；已有凭证和端口会保留。

## 环境变量

可通过环境变量自定义部分配置：

```bash
# 指定 sing-box 版本（推荐 1.13+）
SINGBOX_TAG=v1.13.13 bash sbp.sh

# 跳过启动依赖检查
SBP_SKIP_DEPS=1 bash sbp.sh

# 强制二进制模式（跳过包管理器）
SBP_BIN_ONLY=1 bash sbp.sh

# 调整 UDP NAT 过期时间（默认 10 分钟）
UDP_TIMEOUT=15m bash sbp.sh

# 调整 TCP 保活和 DNS 健康检查周期
TCP_KEEP_ALIVE=30s TCP_KEEP_ALIVE_INTERVAL=30s \
WARP_KEEPALIVE_INTERVAL=25 DNS_HEALTH_INTERVAL=2m bash sbp.sh
```

网络参数会保存到 `/opt/sing-box/env.conf`。DNS 健康检查由轻量 systemd timer 执行；只有当前 DNS 上游发生变化时才会重启 sing-box，并写入切换和重启记录。

## 客户端导入

安装完成后会输出 20 个分享链接，可直接导入：
- v2rayN / v2rayNG
- Clash Meta / Mihomo
- NekoBox / sing-box 客户端
- Shadowrocket / Quantumult X

> AnyTLS 服务端使用 `h2` / `http/1.1` ALPN；分享链接附带 `fp=chrome`。不同客户端对 AnyTLS 链接规范的支持不完全一致；如果客户端无法直接导入，可按输出的服务器、端口、SNI、ALPN 和密码手动添加。

## 致谢

- [Sing-Box](https://github.com/SagerNet/sing-box) - 核心代理程序
- [wgcf](https://github.com/ViRb3/wgcf) - WARP 账户注册工具
- 原作者 Alvin9999

## 许可证

MIT License
