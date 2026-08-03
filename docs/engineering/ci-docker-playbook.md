# CI / Docker 工程手册 (CI & Docker Playbook)

本手册描述宠物领养平台「可复现容器构建 + 依赖安装纪律 + 多环境矩阵 + 可在 CI 机器上运行的流水线」。
本轮在第 1 轮骨架基础上把单一 demo/ci 扩展为 **demo / ci / staging** 三环境矩阵，并把测试阶段实装为 `unit` + `smoke` 两类门禁。命名、目录、镜像策略均为稳定硬约定，后续轮次继续引用。

---

## 1. 目录结构与职责

```
.
├── .ci/
│   ├── pipeline.yml                       # 总入口：阶段顺序、环境矩阵、健康检查位置
│   ├── build.yml                          # 构建阶段：镜像/产物、构建参数、compose 选择、VITE 默认值
│   ├── test.yml                           # 测试阶段：unit + smoke 两类门禁定义
│   ├── release.yml                        # 发布准备阶段：compose 校验、镜像/产物清单
│   ├── config/
│   │   └── env.staging.example            # staging 环境变量示例（假数据，可拷贝为私有 env）
│   ├── scripts/
│   │   ├── run-pipeline.sh                # 总入口驱动，支持 --stages / --test-gate
│   │   ├── build.sh                       # 构建阶段驱动
│   │   ├── test.sh                        # 测试阶段驱动（unit|smoke|all）
│   │   ├── release.sh                     # 发布准备驱动
│   │   ├── lib_compose.sh                 # 共享：PET_APP_ENV -> compose 文件 / 默认 VITE_API_URL
│   │   ├── backend-healthcheck.sh         # 后端存活探测（Node http，可配置重试）
│   │   └── frontend-healthcheck.sh        # 前端存活探测（wget，可配置重试）
│   └── out/                               # 流水线产物（git-ignored）
├── docker-compose.yml                     # demo 默认编排（本地一键演示）
├── docker-compose.ci.yml                  # CI 覆盖层（不暴露宿主机端口、关闭 restart）
├── docker-compose.staging.yml             # staging 覆盖层（准生产验证，绝对 API URL、资源限制）
├── backend/Dockerfile                     # 后端镜像（node:20-slim，npm ci）
└── frontend/Dockerfile                    # 前端镜像（node:20-alpine 构建 + nginx:alpine 运行）
```

`.ci/*.yml` 是**声明式阶段规格**，`.ci/scripts/*.sh` 是对应阶段的**可执行驱动**。总入口 `run-pipeline.sh` 只做阶段调度，不复制各阶段具体命令；环境到 compose 文件的映射统一收敛在 [lib_compose.sh](../../.ci/scripts/lib_compose.sh) 一处。

---

## 2. 环境矩阵（PET_APP_ENV）

| PET_APP_ENV | compose 文件 | PET_VITE_API_URL 默认 | 真实 Mongo | 宿主机端口 | 用途 |
|-------------|--------------|------------------------|------------|------------|------|
| `demo` | `docker-compose.yml` | `/api` | 是 | 发布 3731/8731/5731 | 本地一键演示，走 Nginx `/api` 反代 |
| `ci` | `docker-compose.yml` + `docker-compose.ci.yml` | `/api` | 单测否（smoke 是） | **不发布** | CI 隔离网络；`unit` 用 mongodb-memory-server |
| `staging` | `docker-compose.yml` + `docker-compose.staging.yml` | `http://localhost:8731` | 是 | 发布（可被 env 覆盖） | 单机准生产验证，绝对后端 URL |

**为什么 staging 的 `PET_VITE_API_URL` 与 demo 不同？**
- demo 下前端与后端同源（都经前端 Nginx 的 80 端口），API 走相对路径 `/api`，由 Nginx 反代到后端容器，最简单且无跨域。
- staging 用于“准生产验证”，前端可能被浏览器/预览服务以独立来源打开（例如直接打开静态产物或经独立域名），此时相对 `/api` 不再指回后端；因此默认使用**绝对地址** `http://localhost:8731`（后端发布端口）。真实 staging 主机应通过 `.ci/config/env.staging` 把它覆盖为实际可达的后端地址。
- 该值是**构建期**注入（Vite build arg），不是运行期环境变量。

---

## 3. 环境变量约定（稳定命名）

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `PET_APP_ENV` | `demo` | 运行形态：`demo` \| `ci` \| `staging` |
| `PET_API_PUBLISH_PORT` | `8731` | 后端在宿主机发布的端口（ci 不发布） |
| `PET_WEB_PUBLISH_PORT` | `3731` | 前端在宿主机发布的端口（ci 不发布） |
| `PET_DB_PUBLISH_PORT` | `5731` | MongoDB 在宿主机发布的端口（ci 不发布） |
| `PET_VITE_API_URL` | 按环境（见矩阵） | 前端**构建期**注入的 API 前缀；留空则用各环境默认 |
| `PET_COMPOSE_PROJECT_NAME` | `pet-adoption` | compose 项目名 / 镜像仓库前缀 |
| `PET_RELEASE_TAG` | `latest` | 构建出的镜像标签 |
| `NPM_REGISTRY` | `https://registry.npmmirror.com` | 容器/CI 内 npm 源 |

容器内部监听端口保持稳定：后端容器内 `8731`，前端容器内 `80`，DB 容器内 `27017`。`PET_*_PUBLISH_PORT` 只控制宿主机映射。

---

## 4. 流水线入口与阶段选择

总入口 [run-pipeline.sh](../../.ci/scripts/run-pipeline.sh) 支持按参数只跑部分阶段：

```bash
# 全量：build -> test(unit+smoke) -> release
bash .ci/scripts/run-pipeline.sh

# 只跑构建
bash .ci/scripts/run-pipeline.sh --stages build

# 只跑测试（默认 test-gate=all，即 unit+smoke）
PET_APP_ENV=ci bash .ci/scripts/run-pipeline.sh --stages test

# 只跑测试的 unit 门禁（不需要起 compose，最快）
PET_APP_ENV=ci bash .ci/scripts/run-pipeline.sh --stages test --test-gate unit

# build + test，跳过 release（test 跑 smoke）
PET_APP_ENV=staging bash .ci/scripts/run-pipeline.sh --stages build,test --test-gate smoke
```

各阶段驱动也可单独调用：

```bash
bash .ci/scripts/build.sh                       # 按 PET_APP_ENV 构建
bash .ci/scripts/test.sh unit                   # 单测 + lint（默认，无需真实 Mongo）
bash .ci/scripts/test.sh smoke                  # 起 compose 栈并跑 healthcheck 冒烟
bash .ci/scripts/test.sh all                    # unit 然后 smoke
bash .ci/scripts/release.sh                     # 校验 + 生成 manifest
```

---

## 5. 测试阶段：unit 与 smoke

定义见 [.ci/test.yml](../../.ci/test.yml)，执行见 [.ci/scripts/test.sh](../../.ci/scripts/test.sh)。

### 5.1 unit 门禁
- 工作目录：`/app`（容器内挂载 `backend/`）。
- 镜像：`docker.m.daocloud.io/library/node:20-slim`（Node 20）。
- 安装：`npm ci`（registry 由 `NPM_REGISTRY` 注入）。
- 步骤：`npm run lint` → `npm test -- --runInBand`。
- 数据库：**不依赖真实 Mongo**，由 [tests/setup.js](../../backend/tests/setup.js) 用 `mongodb-memory-server` 在进程内启动。
- `node_modules` 与 mongodb-binaries 使用命名卷缓存，不污染宿主 checkout。
- 产物：`.ci/out/test-report.txt`。

### 5.2 smoke 门禁
- 按 `PET_APP_ENV` 选择 compose 文件（ci 或 staging）。
- 执行 `docker compose up -d --build --wait`：`--wait` 会阻塞到各服务 healthcheck 变 healthy（由第 1 轮外置脚本驱动）。
- 然后通过 `docker compose exec -T <svc> sh /tmp/<svc>-healthcheck.sh` 在**容器内部**探测 `127.0.0.1`，因此 ci 不发布宿主机端口也能冒烟。
- 探测服务由 `SMOKE_SERVICES`（默认 `backend frontend`）控制。
- 失败时自动抓取 `docker compose logs --tail=100`。
- 产物：`.ci/out/smoke-report.txt`。
- 注意：smoke 会保留栈运行（便于排查）；收尾用 `docker compose -p <project> <files> down -v`。

---

## 6. 构建参数透传一致性（VITE_API_URL 链路）

前端 API 前缀的完整传递链如下，三层名称一致：

1. **环境/CLI**：`PET_VITE_API_URL`（compose 变量、`.ci/config/env.staging`、`build.sh`）。
2. **compose build args**：`docker-compose.yml` 与 `docker-compose.staging.yml` 的 `frontend.build.args.VITE_API_URL`（demo 默认 `/api`，staging 默认 `http://localhost:8731`；`build.sh` 也以 `--build-arg VITE_API_URL=...` 显式透传）。
3. **Dockerfile**：[frontend/Dockerfile](../../frontend/Dockerfile) 中 `ARG VITE_API_URL=/api` → `ENV VITE_API_URL=$VITE_API_URL` → `npm run build`（Vite 在构建期读取）。

> 第 2 轮补齐点：修正了 staging overlay 曾把 `VITE_API_URL` 误传给 **backend** build 的问题——后端 Dockerfile 没有该 ARG，该参数只对 frontend 有意义；现在 backend 只接收 `NPM_REGISTRY`。

---

## 7. staging 配置准备（基于 example 生成私有 env）

示例文件：[.ci/config/env.staging.example](../../.ci/config/env.staging.example)（全部为假数据）。

```bash
# 1) 从示例拷贝出本地私有 env（该文件已被 git 忽略，不会被提交）
cp .ci/config/env.staging.example .ci/config/env.staging

# 2) 编辑替换占位值（JWT_SECRET、MONGODB_URI、PET_VITE_API_URL 等）
#    Windows PowerShell:
notepad .ci/config/env.staging

# 3) 用该 env 启动 staging
docker compose --env-file .ci/config/env.staging `
  -f docker-compose.yml -f docker-compose.staging.yml up -d --build
```

`.ci/config/env.staging` 已在 `.gitignore` 中忽略；只有 `env.*.example` 会被跟踪。请勿把真实密钥写入 example。

---

## 8. 健康检查：外置脚本调用约定

健康检查逻辑从启动命令剥离。容器 `CMD` 只启动进程；compose 的 `healthcheck.test` 只读挂载并调用脚本。

- 后端：[backend-healthcheck.sh](../../.ci/scripts/backend-healthcheck.sh)（Node 内置 http，适配 `node:20-slim`），默认 `http://127.0.0.1:8731/health`。
- 前端：[frontend-healthcheck.sh](../../.ci/scripts/frontend-healthcheck.sh)（busybox wget，nginx:alpine 自带），默认 `http://127.0.0.1:80/health`。

两脚本均 `set -eu`，支持 `HEALTH_HOST/PORT/PATH/RETRIES/INTERVAL/TIMEOUT`。staging overlay 复用相同挂载（继承自根 compose）并以 `depends_on: condition: service_healthy` 做启动门控，不内联 curl。

健康端点：后端 `GET /health`；前端 Nginx `location = /health`。

---

## 9. 镜像与依赖纪律

- **基础镜像（DaoCloud 加速）**：前端 builder `node:20-alpine`、运行 `nginx:alpine`；后端 `node:20-slim`；DB `mongo:7`。
- **依赖安装**：Dockerfile 与 CI 全程 `npm ci`（后端生产 `npm ci --omit=dev`），禁止 `npm install`。
- **npm registry**：统一 `ARG NPM_REGISTRY=https://registry.npmmirror.com`，可 `--build-arg` 覆盖。
- **不引入** nx/turborepo/lerna/pnpm-workspace 等 monorepo 工具；编排只用「仓库内 YAML + shell + docker compose」。
- **不新增**与流水线无关的业务依赖。

---

## 10. 常见失败排查

| 现象 | 原因 | 处理 |
|------|------|------|
| `npm ci` 报 lockfile 缺失/不同步 | `package-lock.json` 未提交或过期 | 本地 `npm install` 刷新锁文件并提交；Docker/CI 路径不得用 `npm install` 绕过 |
| registry 超时 | 网络不通 | 确认 `NPM_REGISTRY=npmmirror`，CI 可用 `--build-arg` 覆盖 |
| 端口占用 | demo/staging 端口被占 | 改 `PET_*_PUBLISH_PORT`，或用 `PET_APP_ENV=ci`（不发布宿主端口） |
| healthcheck 假阳性/一直 starting | 后端未连上 DB、路径/端口不符 | 查 `docker compose logs backend`；确认 `/health` 已注册、脚本 `HEALTH_PORT` 与容器内端口一致 |
| smoke 在 ci 下连不上服务 | 误以为需要宿主端口 | smoke 在容器内 `exec` 探测 `127.0.0.1`，无需发布端口；确认 `--wait` 已通过 |
| staging 前端请求打到错误地址 | `PET_VITE_API_URL` 是构建期值且未重建 | 改 env 后必须 `up --build` 重建前端镜像；运行期改 env 不影响已构建产物 |
| `!override` 报错 | Compose 版本过旧 | 升级到 Compose v2.24+ / 新版 Docker Desktop |

---

## 11. 产物

- 镜像：`<project>-backend:<tag>`、`<project>-frontend:<tag>`
- 前端归档：`.ci/out/frontend-dist.tar.gz`
- 发布清单：`.ci/out/release-manifest.md`
- 测试报告：`.ci/out/test-report.txt`、`.ci/out/smoke-report.txt`

`.ci/out/` 为本地/CI 临时产物目录，已被 git 忽略。
