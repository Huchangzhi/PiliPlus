# PiliPlus Web 服务端

无状态转发服务：浏览器页面仍然静态部署，所有 bilibili 请求通过这里转发。
服务端**不保存账号、Cookie、历史或缓存**，这些数据只存在浏览器
（Hive/IndexedDB）中。

## 启动

所有依赖都在项目目录内，不需要全局安装：

```bash
source .tooling/env.sh          # 项目内 PUB_CACHE / npm 缓存 / 镜像
cd server
npm install --no-audit --no-fund  # 安装 undici / ws（项目内 .npmrc 已换源）
node server.mjs
```

默认监听 `http://127.0.0.1:8787`，同时托管 `build/web`（若存在）。
健康检查：`curl http://127.0.0.1:8787/health`。

## 允许的远端地址

默认只允许以下地址，避免服务端被当作开放代理或访问内网：

- `bilibili.com` 及其子域（API、直播、登录、空间等）
- `hdslb.com`、`biliimg.com`（图片/CDN）
- `bilivideo.com` / `bilivideo.cn` / `bilivideo.net`（视频 CDN）
- `b23.tv`（官方短链）
- `upos-*.akamaized.net` / `proxy-*.akamaized.net`（海外视频 CDN）
- `*.szbdyd.com`（B 站镜像 CDN）
- `www.bsbsb.top`（SponsorBlock，可选功能）
- `api/static/gcaptcha4/h5/gt4.geetest.com`（登录验证码）

**防护规则：**

- 拒绝所有 IP 字面量目标（含 IPv6 `::1`、`[::ffff:127.0.0.1]` 等）。
- 对每个域名做 DNS 解析校验，只连接公网地址；回环、RFC1918 私网、
  CGNAT、链路本地、IPv6 ULA/链路本地/组播/映射地址、云元数据地址一律拒绝。
- 重定向目标同样受白名单和 DNS 校验约束。

需要额外域名时通过 `ALLOWED_HOSTS` 追加（逗号分隔后缀），并自行评估风险。

## 配置

复制 `.env.example` 为 `.env` 后自行 export，或直接设置环境变量：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `HOST` | `127.0.0.1` | 监听地址；部署到公网时改为 `0.0.0.0` 并配置反向代理/HTTPS |
| `PORT` | `8787` | 监听端口 |
| `ALLOW_ORIGIN` | `*` | CORS 来源，可填逗号分隔白名单 |
| `PROXY_TOKEN` | 空 | 可选共享令牌，客户端通过 `x-pili-token` 发送 |
| `ALLOWED_HOSTS` | bilibili 系域名 | 额外允许的域名后缀（逗号分隔） |
| `STATIC_DIR` | `../build/web` | 静态页面目录 |
| `LOG_REQUESTS` | `0` | 设为 `1` 时记录方法/域名/路径（不记录 Cookie 与查询串） |

## 接口

- `GET /health`：健康检查与白名单信息。
- `ANY /proxy`：转发请求。目标地址放在 `x-pili-target` 请求头
  （或 `?url=` 参数），只允许白名单域名，默认拒绝内网地址。
- `GET /`：静态页面或启动说明。

浏览器禁止脚本设置 `Cookie`、`Referer`、`User-Agent` 等请求头，因此 Web
客户端会通过 `x-pili-cookie` / `x-pili-referer` / `x-pili-user-agent`
传递，服务端再还原。上游的 `Set-Cookie` 通过 `x-pili-set-cookie`
（base64 JSON）返回给浏览器写入本地 Cookie Jar。

## 隐私与安全

- 不落盘、不记录 Cookie；仅做流式转发。
- 默认只监听本机。
- 域名白名单防止被当作开放代理/SSRF 跳板。
- 如需公网部署，建议启用 `PROXY_TOKEN` 并由反向代理提供 HTTPS。

## 打包部署

静态端（Cloudflare Pages / 任意静态托管）：

```bash
REBUILD=1 tool/web/package_web.sh
# 产物：dist/piliplus-web-cf-pages.zip（index.html 在压缩包根目录）
```

上传前编辑压缩包内的 `pili-config.js`，把默认服务端指向你的地址：

```js
window.PILI_SERVER = 'https://pili-api.example.com';
```

也可以在构建时写死：`REBUILD=1 PILI_SERVER=https://pili-api.example.com tool/web/package_web.sh`。
用户仍可在设置中覆盖。

服务端单文件包：

```bash
tool/web/package_server.sh
# 产物：dist/piliplus-server-node.zip
# 内含 pili-server.mjs（已打包 undici/ws）、Dockerfile、.env.example、README.txt
```

```bash
HOST=0.0.0.0 PORT=8787 node pili-server.mjs
# 或
docker build -t piliplus-relay . && docker run -d -p 8787:8787 piliplus-relay
```

服务端只监听白名单域名并校验 DNS，默认拒绝内网/IP 字面量；公开部署时请放在
HTTPS 反向代理之后，并按需设置 `ALLOW_ORIGIN` 与 `PROXY_TOKEN`。
