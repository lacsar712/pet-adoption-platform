# CI / Docker Playbook — Pet Adoption Platform

本文件是「可复现容器构建 + 依赖安装纪律 + CI 流水线骨架」的唯一权威说明。
后续轮次（staging / 门禁 / 一致性审计）会在此约定之上扩展，命名与目录视为硬前提。

---

## 1. 目录结构（`.ci/` 职责）

```
.ci/
├── build.yml                  # 构建阶段：如何构建前后端镜像/产物（声明式）
├── test.yml                   # 测试阶段：unit(jest 内存 Mongo) + smoke(healthcheck) 双门禁（声明式）
├── release.yml                # 发布准备：镜像标签、compose 校验、产物清单（声明式）
├── pipeline.yml               # 总入口（编排）：按序 include build→test→release，不复制具体命令
├── config/
│   └── env.staging.example    # staging 环境变量键名与假示例值（拷贝为私有 env 使用）
├── out/
│   └── release-manifest.md    # release artifact_manifest 门禁生成（运行时产出）
└── scripts/
    ├── pipeline.sh            # 总入口驱动：仅调度，把阶段委派给 run-stage.sh
    ├── run-stage.sh           # 单阶段执行器：承载每个阶段的具体命令 + 环境矩阵选择
    ├── release-manifest.sh    # 生成 .ci/out/release-manifest.md（外置，供 release 门禁调用）
    ├── backend-healthcheck.sh # 后端存活探测（外置，可配 host/port/retries/interval）
    └── frontend-healthcheck.sh# 前端存活探测（外置，探测 Nginx /healthz）
docker-compose.yml             # 本地一键演示默认文件（demo，保留不变）
docker-compose.ci.yml          # CI 覆盖层：参数化端口、构建 args、外置 healthcheck、db 不发布
docker-compose.staging.yml     # staging 覆盖层：真实 Mongo、绝对 API URL、重启/健康依赖策略
docs/engineering/ci-docker-playbook.md      # 本文件
docs/engineering/consistency-audit.md       # 跨轮一致性审计（第 3 轮）
docs/engineering/release-manifest.example.md # release 归档清单模板
```

设计原则：
- **阶段拆分**：build / test / release 各自独立，不堆进一个超长文件。
- **总入口只编排**：`pipeline.yml` 用 include 标出调用关系；`pipeline.sh` 只调度，不复制粘贴各阶段命令，具体命令集中在 `run-stage.sh`。
- **健康检查外置**：CMD / compose command 只负责启动进程；healthcheck 调用 `.ci/scripts/*-healthcheck.sh`，不在 YAML 里内联 curl 长命令。

---

## 2. 环境变量与端口约定

| 变量 | 含义 | 默认值 |
| --- | --- | --- |
| `PET_APP_ENV` | 环境标识，支持 `demo` \| `ci` \| `staging` | `ci`（脚本内） |
| `PET_API_PUBLISH_PORT` | 后端宿主机发布端口 | `8731` |
| `PET_WEB_PUBLISH_PORT` | 前端宿主机发布端口 | `3731` |
| `PET_DB_PUBLISH_PORT` | 数据库宿主机发布端口 | `5731` |
| `PET_VITE_API_URL` | 前端构建期 API 前缀 | demo/ci 默认 `/api`；staging 默认 `http://localhost:8731` |
| `PET_COMPOSE_PROJECT_NAME` | compose 项目名 | `pet-adoption` |
| `PET_CI_STAGES` | 总入口按序运行的阶段子集 | `build test release` |
| `PET_TEST_GATES` | test 阶段运行的门禁子集 | `unit smoke` |
| `PET_TEST_COVERAGE` | 打开 coverage 存在性门禁（`1` 开启） | `0`（关闭） |
| `PET_RELEASE_GATES` | release 阶段运行的门禁子集 | `validate image_exists health_gate artifact_manifest` |
| `PET_RELEASE_ENV` | release health_gate 探测的目标环境 | `staging` |
| `PET_RELEASE_TAG` | release 镜像 tag 的可变后缀 | `local` |

后端容器内监听端口与现网一致（`8731`），未改成 3000/5173。

---

## 3. 环境矩阵与启动 / 构建命令

### 3.0 环境矩阵表（demo / ci / staging）

| 维度 | demo | ci | staging |
| --- | --- | --- | --- |
| compose 文件 | `docker-compose.yml` | base + `docker-compose.ci.yml` | base + `docker-compose.staging.yml` |
| `PET_APP_ENV` | `demo` | `ci` | `staging` |
| `PET_VITE_API_URL` | `/api`（经 Nginx 反代） | `/api` | `http://localhost:8731`（绝对源） |
| 是否跑真实 Mongo | 是（一键演示） | 否（单测走内存 Mongo；db 端口不发布） | 是（准生产集成校验） |
| db 端口是否对外 | 是（5731） | 否（`ports: !reset []`） | 是（5731） |
| 典型验证命令 | `docker compose -p pet-adoption up --build` | `PET_APP_ENV=ci sh .ci/scripts/pipeline.sh` | `PET_APP_ENV=staging PET_CI_STAGES="build test" sh .ci/scripts/pipeline.sh` |

> **为什么 staging 的 API URL 与 demo 的 `/api` 不同？**
> demo/ci 下浏览器命中 Nginx 源站，`/api` 被反向代理到后端，相对前缀即可工作。
> staging 用于把前端当作独立发布的服务去验证它与「独立发布端口的后端」通信，
> 因此构建期烘入绝对源 `http://localhost:8731`，用以真实检验 CORS 与后端发布端口。
> 后端 `app.js` 的 CORS 允许列表已包含 `http://localhost:3731`，前端命中后端 8731 时会走该来源校验。

### demo（本地一键演示，使用根目录默认 compose）

```bash
# 构建并启动全套（前端 3731 / 后端 8731 / DB 5731）
docker compose -p pet-adoption up --build
# 浏览器访问 http://localhost:3731
```

### ci（CI 态，叠加 docker-compose.ci.yml）

```bash
# 全流水线（build -> test -> release）
sh .ci/scripts/pipeline.sh

# 只构建镜像 / 只跑测试 / build+test（参数：PET_CI_STAGES）
PET_CI_STAGES="build" sh .ci/scripts/pipeline.sh
PET_CI_STAGES="test"  sh .ci/scripts/pipeline.sh
PET_CI_STAGES="build test" sh .ci/scripts/pipeline.sh

# test 阶段门禁选择（参数：PET_TEST_GATES）
PET_TEST_GATES="unit"  PET_CI_STAGES="test" sh .ci/scripts/pipeline.sh   # 只跑单测
PET_TEST_GATES="smoke" PET_CI_STAGES="test" sh .ci/scripts/pipeline.sh   # 只跑冒烟

# 直接构建 CI 镜像（等价于 build 阶段）
docker compose -p pet-adoption \
  -f docker-compose.yml -f docker-compose.ci.yml \
  build --build-arg VITE_API_URL=/api
```

CI 覆盖层要点：
- 数据库端口 **不** 发布到宿主机（`ports: !reset []`），避免 CI 机器端口抢占。
- 前端 `VITE_API_URL` 通过构建 arg 由 `PET_VITE_API_URL` 透传。
- 后端 / 前端 healthcheck 挂接外置脚本（只读挂载到 `/opt/healthcheck.sh`）。

### staging（准生产验证，叠加 docker-compose.staging.yml）

```bash
# 1) 基于 example 生成本地私有 env（见 §7）
cp .ci/config/env.staging.example .env.staging.local
# 编辑 .env.staging.local，替换为真实值

# 2) 用私有 env 起 staging（真实 Mongo + 绝对 API URL）
docker compose --env-file .env.staging.local \
  -f docker-compose.yml -f docker-compose.staging.yml up -d --build

# 3) 或经流水线（会按 PET_APP_ENV 选择 staging 覆盖层）
PET_APP_ENV=staging PET_CI_STAGES="build test" sh .ci/scripts/pipeline.sh
```

staging 覆盖层要点：
- 服务名语义不变（db/backend/frontend）；未引入 Swarm/K8s。
- 真实 Mongo 服务并发布 5731；`restart: unless-stopped` 提供准生产韧性。
- `depends_on` 使用 `condition: service_healthy`：backend 等 db 健康、frontend 等 backend 健康。
- 前端构建期 `PET_VITE_API_URL` 默认 `http://localhost:8731`。
- healthcheck 复用第 1 轮外置脚本（只读挂载），不内联 curl。

---

## 4. 镜像与依赖纪律

- 基础镜像：
  - 前端 builder：`node:20-alpine`（DaoCloud 加速）
  - 前端 runtime：`nginx:alpine`
  - 后端 build/run：`node:20-slim`（DaoCloud 加速）
- 依赖安装：Docker / CI 路径 **一律 `npm ci`**，禁止在镜像构建脚本里写 `npm install`。
  （本地开发文档里 `npm install` 仅作说明用途，允许保留。）
- npm registry 在 Docker / CI 中统一为 `https://registry.npmmirror.com`。
- 不引入 nx / turborepo / lerna / pnpm-workspace 等 monorepo 编排工具，也不引入新的 Node 侧 CI 封装框架；编排只用 **YAML 配置 + shell 脚本 + docker compose**。

### 4.1 前端构建参数传递链（第 2 轮补齐）

前端 API 前缀的名称/传递链在三处保持一致，构成完整闭环：

```
PET_VITE_API_URL (环境变量, run-stage.sh 按 env 设默认)
   │  compose build args:
   ▼
VITE_API_URL (docker-compose.ci.yml / staging.yml 的 build.args)
   │  Dockerfile:
   ▼
ARG VITE_API_URL  ->  ENV VITE_API_URL  ->  npm run build 读取
```

- 第 1 轮 `docker-compose.ci.yml` 已用 `args.VITE_API_URL: ${PET_VITE_API_URL}` 透传；
  第 1 轮 `docker-compose.yml`（demo）依赖 Dockerfile 内 `ARG VITE_API_URL=/api` 默认值。
- 本轮 `docker-compose.staging.yml` 复用同一链路，仅把默认值改为 `http://localhost:8731`。
- 命令行覆盖示例：`docker compose ... build --build-arg VITE_API_URL=/api`。

---

## 4.2 发布门禁与镜像 tag 规则（第 3 轮）

release 阶段只做「发布准备」，**不推送镜像、不做任何 git 操作**。门禁由
`PET_RELEASE_GATES` 选择（默认全开），具体命令在 `run-stage.sh` 的 `release_gate_*`：

| 门禁 | 作用 | 失败即 release 失败 |
| --- | --- | --- |
| `validate` | 校验 base+ci、base+staging 覆盖层可合并 | 是 |
| `image_exists` | 确认 frontend/backend 镜像已按约定 tag 构建 | 是 |
| `health_gate` | 对 `PET_RELEASE_ENV`（默认 staging）跑第 1 轮两个 healthcheck 脚本 | 是 |
| `artifact_manifest` | 生成 `.ci/out/release-manifest.md` | 是 |

镜像 tag 规则（**第 3 轮统一，含迁移**）：

```
${PET_COMPOSE_PROJECT_NAME}-${PET_APP_ENV}-${PET_RELEASE_TAG}
例：pet-adoption-staging-local
```

> 迁移说明：第 1 轮 tag 为 `${PET_APP_ENV}-${PET_RELEASE_TAG}`（无项目名前缀），
> 在多环境/多项目下会碰撞。第 3 轮统一加 `PET_COMPOSE_PROJECT_NAME` 前缀，
> `build` 阶段会把 compose 构建出的镜像按此 tag 打标，供 `image_exists` 核查。
> 详见 `docs/engineering/consistency-audit.md`。

运行示例：

```bash
# 先构建并打 tag（build 阶段会 docker tag 到发布 tag）
PET_APP_ENV=staging PET_RELEASE_TAG=local sh .ci/scripts/run-stage.sh build

# 起 staging 栈后跑完整 release 门禁
PET_APP_ENV=staging sh .ci/scripts/run-stage.sh release

# 只生成归档清单（跳过其他门禁）
PET_RELEASE_GATES="artifact_manifest" sh .ci/scripts/run-stage.sh release
```

质量门禁（接在 test 阶段，非 release）：coverage 存在性检查默认关闭，
`PET_TEST_COVERAGE=1` 开启后跑 `npm test -- --coverage` 并检查
`backend/coverage/` 下报告是否生成（不设阈值、不改业务测试）：

```bash
PET_TEST_COVERAGE=1 PET_TEST_GATES="unit" PET_CI_STAGES="test" sh .ci/scripts/pipeline.sh
```

---

## 5. 健康检查脚本如何被调用

- 后端存活端点：应用新增极简 `GET /health`（同时经 Nginx 反代暴露为 `GET /api/health`），仅返回 `{status:"ok"}`。
- 前端存活路径：Nginx 新增 `location = /healthz`，直接返回 `200 ok`（不依赖后端）。
- `backend-healthcheck.sh` / `frontend-healthcheck.sh` 支持环境变量：
  `HC_HOST` / `HC_PORT` / `HC_PATH` / `HC_RETRIES` / `HC_INTERVAL` / `HC_TIMEOUT`，
  内部按 `retries × interval` 重试，`set -eu` 严格模式，优先 curl 回退 wget。
- compose 的 healthcheck 只调用脚本（`sh /opt/healthcheck.sh`），不内联 curl。

从宿主机手动探测：

```bash
# 后端（容器已发布 8731）
HC_PORT=8731 sh .ci/scripts/backend-healthcheck.sh
# 前端（容器已发布 3731）
HC_PORT=3731 sh .ci/scripts/frontend-healthcheck.sh
```

---

## 6. 常见失败排查

| 症状 | 原因 | 处理 |
| --- | --- | --- |
| `npm ci` 报错找不到 lockfile | `package-lock.json` 缺失/未提交 | 本地 `npm install` 生成并提交 lockfile；Docker 路径不改用 npm install |
| 拉包超时 | registry 未走镜像 | 确认走 `https://registry.npmmirror.com`；基础镜像走 DaoCloud 加速 |
| 端口占用（3731/8731/5731） | 宿主机已有进程 | CI 用 `docker-compose.ci.yml`（db 不发布端口）；或改 `PET_*_PUBLISH_PORT` |
| healthcheck 假阳性/假阴性 | 探测过早或路径错 | 调 `HC_RETRIES`/`HC_INTERVAL`/`start_period`；确认 `/health`、`/healthz` 路径 |
| CI 单测连了真实 Mongo | 误把 db 服务当单测前置 | 单测走 jest + mongodb-memory-server，真实 Mongo 仅供 demo/集成 |

---

## 7. 基于 example 生成本地私有 env（staging 密钥工程化）

staging 需要的环境变量键名与示例值集中在 `.ci/config/env.staging.example`（示例值全部为假数据，大写蛇形命名）。使用方式仅涉及文件拷贝与值替换：

```bash
# 1) 拷贝模板为本地私有文件（命名建议 .env.staging.local）
cp .ci/config/env.staging.example .env.staging.local

# 2) 编辑 .env.staging.local，把 JWT_SECRET / MONGODB_URI 等替换为真实值

# 3) 用 --env-file 注入到 staging compose
docker compose --env-file .env.staging.local \
  -f docker-compose.yml -f docker-compose.staging.yml up -d --build
```

包含的键（示例值均为假数据）：`PET_APP_ENV`、`PET_COMPOSE_PROJECT_NAME`、
`PET_API_PUBLISH_PORT`、`PET_WEB_PUBLISH_PORT`、`PET_DB_PUBLISH_PORT`、
`PET_VITE_API_URL`、`JWT_SECRET`、`MONGODB_URI`、`SEED_DEMO`、`UPLOAD_DIR`、
`NODE_ENV`、`PORT`。

说明：
- 不接任何真实云服务；示例值仅供本地/准生产联调。
- 私有 env 文件（如 `.env.staging.local`）不应纳入版本库，请依据现有忽略策略处理；本文不涉及任何其他版本控制操作。
- `docker-compose.staging.yml` 的 backend 环境变量对这些键提供了假数据兜底默认值，即使不传 `--env-file` 也能 `up`，便于快速冒烟。

