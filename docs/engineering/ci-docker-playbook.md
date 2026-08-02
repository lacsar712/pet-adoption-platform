# CI / Docker 工程手册（ci-docker-playbook）

本手册约定「宠物领养平台」的容器构建、依赖安装纪律与流水线入口。
后续门禁与一致性审计均建立在本文件的命名与目录约定之上。

## 1. 目录结构

```
.ci/
├── pipeline.yml                  # 流水线总入口：只声明 include 顺序（build -> test -> release）
├── build.yml                     # 构建阶段：lockfile 校验 + docker compose 构建前后端镜像
├── test.yml                      # 测试阶段：unit / smoke / coverage（可选）三类门禁
├── release.yml                   # 发布门禁：validate / image_exists / health_gate / artifact_manifest
├── config/
│   └── env.staging.example       # staging 环境变量键名与示例值（假数据，大写蛇形命名）
├── out/                          # 流水线产物（如 release-manifest.md，自动生成）
└── scripts/
    ├── pipeline.sh               # 薄调度器，按 pipeline.yml 的顺序调度各阶段 YAML（不含具体命令）
    ├── run-stage.sh              # 阶段执行器：提取单个阶段 YAML 中的单行 run: 命令逐条执行，支持 gate 过滤
    ├── release-manifest.sh       # 生成 .ci/out/release-manifest.md 发布归档清单
    ├── backend-healthcheck.sh    # 后端存活探测（host/port/path/retries/interval 均可配置）
    └── frontend-healthcheck.sh   # 前端（Nginx）存活探测（参数同上）

另见 `docs/engineering/consistency-audit.md`（跨轮一致性审计，每轮复核约定是否自洽）。
```

约定：各阶段 YAML 中的 `run:` 必须是**单行命令**；编排逻辑只在 `pipeline.yml` /
`pipeline.sh`，阶段命令只存在于各自的阶段 YAML 中，不允许复制回总入口。

## 2. 环境变量与端口约定

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `PET_APP_ENV` | `demo` | 运行环境标识：`demo` / `ci` / `staging` |
| `PET_API_PUBLISH_PORT` | `8731` | 后端宿主机发布端口（容器内监听同为 8731） |
| `PET_WEB_PUBLISH_PORT` | `3731` | 前端宿主机发布端口（容器内 Nginx 为 80） |
| `PET_DB_PUBLISH_PORT` | `5731` | MongoDB 宿主机发布端口（CI 叠加文件下不发布） |
| `PET_VITE_API_URL` | `/api`（demo/ci）；`http://localhost:8731`（staging） | 前端构建期注入的 API 前缀 |
| `PET_COMPOSE_PROJECT_NAME` | `pet-adoption` | compose 项目名，决定镜像名 `<project>-backend/frontend` |
| `PET_IMAGE_TAG` | `ci-local` | 发布 tag 的环境后缀段（见第 4 节 tag 规则） |
| `PET_CI_STAGES` | `build test release` | `pipeline.sh` 要执行的阶段子集 |
| `PET_CI_GATES` | 空（全部） | 只执行指定 gate（test：`unit`/`smoke`/`coverage`；release：`validate`/`image_exists`/`health_gate`/`artifact_manifest`） |

## 3. 环境矩阵

| 环境 | `PET_APP_ENV` | compose 文件组合 | 前端 API URL（`PET_VITE_API_URL`） | 是否跑真实 Mongo | 验证命令 |
| --- | --- | --- | --- | --- | --- |
| demo | `demo` | `docker-compose.yml` | `/api`（同源，Nginx 反代到后端） | 是，发布 `5731` | `docker compose up --build -d --wait` |
| ci | `ci` | `docker-compose.yml` + `docker-compose.ci.yml` | `/api` | db 不发布宿主机端口；单测一律走 mongodb-memory-server | `sh .ci/scripts/pipeline.sh` |
| staging | `staging` | `docker-compose.yml` + `docker-compose.staging.yml` | `http://localhost:8731`（浏览器直连后端发布端口） | 是（准生产验证真实驱动行为） | 见下方 staging 小节 |

**为什么 staging 的 API URL 与 demo 的 `/api` 不同**：demo 验证的是「同源 +
Nginx 反代」链路；staging 的目的之一是验证「浏览器直连后端发布端口 + CORS」
链路（后端 `allowedOrigins` 已包含 `http://localhost:3731`），避免把 Nginx
反代配置的正确性混进准生产验证结论。两条链路都能工作，才说明前后端各自
的部署单元是独立可用的。

### staging 配置准备（密钥/配置的工程化）

staging 需要的变量键名固定在 `.ci/config/env.staging.example`（示例值全部为
假数据，大写蛇形命名）。生成本地私有 env 的步骤：

```bash
# 1) 拷贝 example 为本地私有文件（不入库，.gitignore 已覆盖 .env.* 之外的
#    env.staging.local 需要自行留意不要提交）
cp .ci/config/env.staging.example .ci/config/env.staging.local

# 2) 用编辑器打开 env.staging.local，按需替换示例值（JWT_SECRET 等）

# 3) 以 --env-file 叠加 staging 覆盖文件启动
docker compose --env-file .ci/config/env.staging.local \
  -f docker-compose.yml -f docker-compose.staging.yml up -d --build --wait
```

> 注意：staging 前端直连 `http://localhost:8731`，因此 **staging 镜像重建前**
> 必须先确定 `PET_VITE_API_URL`（它是构建期注入的，改值必须重新 build）。

## 4. 流水线调度（阶段与门禁）

可执行入口为 `.ci/scripts/pipeline.sh`（薄调度器，只按 `pipeline.yml` 的
include 顺序调度，本身不含阶段命令）。通过两个环境变量选择执行范围：

```bash
sh .ci/scripts/pipeline.sh                                  # 完整：build -> test -> release
PET_CI_STAGES="build"      sh .ci/scripts/pipeline.sh       # 只跑 build
PET_CI_STAGES="test"       sh .ci/scripts/pipeline.sh       # 只跑 test（全部门禁）
PET_CI_STAGES="build test" sh .ci/scripts/pipeline.sh       # build + test
PET_CI_STAGES="test" PET_CI_GATES="unit"  sh .ci/scripts/pipeline.sh   # 只跑 unit 门禁
PET_CI_STAGES="test" PET_CI_GATES="smoke" sh .ci/scripts/pipeline.sh   # 只跑 smoke 门禁
```

也可以不经总入口，直接执行单个阶段/门禁：

```bash
sh .ci/scripts/run-stage.sh .ci/test.yml          # test 全部门禁
sh .ci/scripts/run-stage.sh .ci/test.yml unit     # 只跑 unit
sh .ci/scripts/run-stage.sh .ci/test.yml smoke    # 只跑 smoke
```

### 测试阶段的门禁定义

- **unit**：工作目录为仓库根目录（命令显式使用 `npm --prefix backend`），
  Node 版本 20（与 `node:20-alpine/slim` 镜像一致）；第一步必须先
  `npm ci`（registry 固定 npmmirror），随后 eslint 与 jest。
  jest 走 `mongodb-memory-server`（内存 Mongo，见 `backend/tests/setup.js`），
  **不需要也不允许**先启动真实 mongo 容器。
- **smoke**：以 ci 叠加文件起完整栈（`up -d --wait` 本身依赖外置
  healthcheck 脚本），再从宿主机经发布端口调用第 1 轮的
  `backend-healthcheck.sh` / `frontend-healthcheck.sh` 复探，最后 `down` 收尾
  （若中途失败，需手工执行同参数的 `down`）。
  若要对 staging 栈做等价冒烟，起栈命令换成 staging 组合即可，
  healthcheck 脚本调用方式不变。
- **coverage**（可选，默认关闭）：`PET_CI_STAGES="test" PET_CI_GATES="coverage"
  sh .ci/scripts/pipeline.sh` 开启。执行 `jest --coverage`（仍走
  mongodb-memory-server）后只做**报告存在性检查**（`backend/coverage/lcov.info`），
  不卡覆盖率阈值，也未改动 jest 业务配置。

### 发布阶段的门禁定义（release.yml）

- **validate**：ci 与 staging 两种 compose 叠加组合的 `config --quiet` 解析校验。
- **image_exists**：确认 `<project>-backend:latest` / `<project>-frontend:latest`
  已构建（compose 自动命名），并打发布 tag。tag 规则（第 3 轮定版）：
  `${PET_COMPOSE_PROJECT_NAME}-<service>:${PET_APP_ENV}-${PET_IMAGE_TAG}`，
  例：`pet-adoption-backend:staging-ci-local`。（旧规则 `<project>-<service>:ci-local`
  与根目录 `release-manifest.txt` 已废弃，迁移说明见 consistency-audit.md 探针 H。）
- **health_gate**：对目标环境（默认 staging 组合）`up -d --wait` 起栈，
  依次执行两个外置 healthcheck 脚本，任一失败即 release 失败，最后 `down` 收尾。
- **artifact_manifest**：执行 `.ci/scripts/release-manifest.sh` 生成
  `.ci/out/release-manifest.md`（镜像名、tag 规则、关键 compose 文件、
  env example、healthcheck 脚本路径）。

release 全程只做本地/CI 内动作，不推送远端镜像仓库、不做任何 git 操作。

## 5. 构建参数透传链（VITE_API_URL）

`PET_VITE_API_URL` 的完整传递链（四处名称保持一致）：

```
宿主机环境变量 PET_VITE_API_URL
  → compose build.args.VITE_API_URL（docker-compose.yml / .ci.yml / .staging.yml 中
    均为 VITE_API_URL: ${PET_VITE_API_URL:-<各环境默认值>}）
  → frontend/Dockerfile 的 ARG VITE_API_URL + ENV VITE_API_URL
  → Vite 构建期注入 import.meta.env.VITE_API_URL
```

覆盖示例（demo/ci 同理，改 staging 组合即可）：

```bash
PET_VITE_API_URL=/api docker compose -f docker-compose.yml build frontend
```

## 6. 镜像与依赖纪律

- 基础镜像：
  - 前端 builder：`node:20-alpine`（DaoCloud 等价加速镜像 `docker.m.daocloud.io/library/node:20-alpine`）
  - 后端：`node:20-slim`（`docker.m.daocloud.io/library/node:20-slim`）
  - 前端运行态：`nginx:alpine`（`docker.m.daocloud.io/library/nginx:alpine`）
  - 数据库：`mongo:7`（`docker.m.daocloud.io/library/mongo:7`）
- Docker/CI 路径安装 npm 依赖**只允许 `npm ci`**（前提是对应目录存在
  `package-lock.json`，build 阶段第一步即校验 lockfile 存在）。
  `npm install` 仅允许出现在本地开发的口头/文档说明中，禁止写进 Dockerfile 与 CI。
- npm registry 在 Docker/CI 中统一为 `https://registry.npmmirror.com`
  （Dockerfile 内 `npm config set registry`；CI 宿主机用 `--registry=` 参数）。
- 不引入 nx / turborepo / lerna / pnpm-workspace 等 monorepo 编排工具；
  编排只用「仓库内 YAML + shell 脚本 + docker compose」。

## 7. 健康检查如何被调用

健康检查逻辑全部外置在 `.ci/scripts/` 下，容器启动命令（CMD）只负责启动进程：

- **后端**：`backend-healthcheck.sh` 探测 `http://<host>:<port>/health`
  （Express 的 `GET /health`，不依赖 Mongo；经 Nginx 反代时为 `/api/health`，
  因为 `nginx.conf` 将 `/api/` 代理到后端 `/`）。
- **前端**：`frontend-healthcheck.sh` 探测 `http://<host>:<port>/healthz`
  （`nginx.conf` 中 `location = /healthz` 直接返回 200）。

调用方式：

1. **compose healthcheck（容器内）**：根 `docker-compose.yml` 把 `./.ci/scripts`
   只读挂载到 `/healthcheck`，`healthcheck.test` 调用脚本并显式传
   `127.0.0.1 <容器内端口> <路径>`；staging/ci 叠加文件**继承**该挂接，
   不重复声明。服务环境变量 `HEALTHCHECK_RETRIES=1` 使脚本单次探测，
   重试节奏由 compose 的 `interval/retries` 控制，避免双重重试。
2. **宿主机/CI 冒烟**：`sh .ci/scripts/backend-healthcheck.sh localhost 8731 /health`
   （脚本默认重试 12 次、间隔 5s，可用 `HEALTHCHECK_RETRIES` / `HEALTHCHECK_INTERVAL` 覆盖）。
3. 探测工具在脚本内按 `curl -> wget -> node(fetch)` 自动降级，
   保证在 `node:20-slim`（无 curl/wget）与 `nginx:alpine`（busybox wget）中都能运行。

> 注意：`.ci/scripts/*.sh` 必须以 **LF** 行尾保存（Windows 上请确认编辑器 /
> `core.autocrlf` 设置），否则挂载进容器后 `sh` 会解析失败。

## 8. 常见失败与排查

| 症状 | 原因 | 处理 |
| --- | --- | --- |
| `npm ci` 报 `EUSAGE` / lockfile 相关错误 | `package-lock.json` 缺失或与 package.json 不同步 | 本地 `npm install` 一次生成/同步 lockfile 并提交；build 阶段第一步会提前拦截 |
| 构建阶段 npm 卡死/超时 | registry 不可达 | 确认走 `https://registry.npmmirror.com`（Dockerfile 与 CI 命令均已内置）；检查代理 |
| `docker compose up` 报端口被占用 | 3731/8731/5731 被本机其他进程占用 | 用 `PET_WEB_PUBLISH_PORT` / `PET_API_PUBLISH_PORT` / `PET_DB_PUBLISH_PORT` 改端口，或停掉占用进程 |
| 容器反复 unhealthy 但进程活着 | healthcheck 假阳性：脚本行尾 CRLF、路径写错、容器内无探测工具 | 确认脚本 LF 行尾；手工 `docker exec <容器> sh /healthcheck/backend-healthcheck.sh` 看输出；脚本已内置 curl/wget/node 降级 |
| `up -d --wait` 一直等待 | 某个服务 healthcheck 持续失败 | `docker compose ps` 看哪个服务 unhealthy，再 `docker inspect --format '{{json .State.Health}}' <容器>` 看探测日志 |
| CI 中 db 端口冲突 | 用了 demo 单文件启动 | CI 必须叠加 `-f docker-compose.ci.yml`（db 不发布宿主机端口） |
| staging 前端请求打到了 `/api` | `PET_VITE_API_URL` 是构建期注入，改值后未重建镜像 | 改值后必须 `--build` 重建 frontend（见第 3、5 节） |
| staging 直连后端报 CORS | 浏览器 Origin 不在后端 `allowedOrigins` | 确认前端访问入口是 `http://localhost:3731`（已在白名单） |
| compose 报 `!reset` 解析错误 | Docker Compose 版本低于 v2.24 | 升级 Docker Desktop |
