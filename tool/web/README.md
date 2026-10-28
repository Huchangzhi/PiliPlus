# Web 构建工具链

工具与依赖全部留在仓库内（`.tooling/`、`server/node_modules/`，都已 gitignore）。
删掉也不会丢，恢复只要一条命令：

```bash
tool/web/setup_toolchain.sh     # 拉 Flutter SDK（国内镜像）+ precache + pub get + 打补丁 + npm install
FLUTTER_VERSION=3.47.7 tool/web/setup_toolchain.sh
FLUTTER_MIRROR=https://storage.googleapis.com tool/web/setup_toolchain.sh   # 换源
```

之后：

```bash
tool/web/build_web.sh                       # 产出 build/web
REBUILD=1 tool/web/package_web.sh           # dist/piliplus-web-cf-pages.zip（CF Pages 直传）
PILI_SERVER=https://api.example.com REBUILD=1 tool/web/package_web.sh   # 编译期写死默认服务端
tool/web/package_server.sh                  # dist/piliplus-server-node.zip（单文件 + Dockerfile）
```

## 目录组成

| 路径 | 内容 | 是否 gitignore |
| --- | --- | --- |
| `tool/web/toolchain/env.sh` | 配置**模板**：仓库内 FLUTTER_ROOT / PUB_CACHE / NPM_CONFIG_CACHE + 国内镜像 + `GIT_CONFIG_GLOBAL` | 否（勿删） |
| `tool/web/toolchain/gitconfig` | 配置**模板**：只给 pub 子进程用的 GitHub 镜像 insteadOf，不动用户全局配置 | 否（勿删） |
| `.tooling/env.sh`、`.tooling/gitconfig` | 上面两份的运行时副本，setup 脚本缺失时自动拷回 | 是 |
| `.tooling/flutter` | Flutter SDK（tar.xz 解包，约 2.5GB） | 是 |
| `.tooling/pub-cache`、`.tooling/npm-cache` | 包与引擎产物缓存 | 是 |
| `server/node_modules` | 中转服务端依赖（undici / ws / esbuild） | 是 |

## 补丁

- `apply_sdk_patches.sh`：给 Flutter SDK 打 Web 相关补丁（幂等）。
- `patch_packages.sh`：给 pub 包打补丁（catcher_2 去 dart:ffi、cached_network_image 哈希与 Web loader、GetX 的 `Platform` 守卫、media_kit_video 自适应布局）。

SDK 或 pub-cache 一旦被重新下载，这些补丁必须重打 —— 所以 `setup_toolchain.sh`
已经把两步串在里面，跑完即可直接 `build_web.sh`。

## 版本

Flutter 3.47.7 / Dart 3.13.5 / Node ≥ 20（`server/.npmrc` 已换 npmmirror）。
构建 Web 需要 `--no-wasm-dry-run`（FFI 会在 dry run 阶段编译失败），`build_web.sh` 已带上。
