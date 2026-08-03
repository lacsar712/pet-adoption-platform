# CI / Docker 工程手册（ci-docker-playbook）

本手册覆盖「可复现的容器构建 + 依赖安装纪律 + 多环境矩阵 + 可在 CI 机器上跑的流水线」。
第 1 轮建立了骨架与 demo/ci 两种形态；第 2 轮扩展出 `staging`、把 test 阶段实装为
`unit` + `smoke` 两道门禁，并让总入口可按参数选择执行哪些阶段。

---

## 1. 目录结构

```
.
├── docker-compose.yml            # demo 态默认编排（本地一键启动）
├── docker-compose.ci.yml         # ci 态覆盖（不暴露宿主机端口、收紧 healthcheck）
├── docker-compose.staging.yml    # staging 态覆盖（绝对 API URL、准生产验证）
├── .ci/
│   ├── pipeline.yml              # 流水线总入口声明：build -> test(unit+smoke) -> release
│   ├── build.yml                 # 构建阶段声明
│   ├── test.yml                  # 测试阶段声明（unit + smoke 两道门禁）
│   ├── release.yml               # 发布准备阶段声明（compose 校验、标签、产物清单）
│   ├── config/
│   │   └── env.staging.example   # staging 环境变量示例（假数据，提交入库）
│   └── scripts/
│       ├── run-pipeline.sh            # shell 驱动入口，按参数调度阶段，不复制阶段命令
│       ├── stage-build.sh             # 构建阶段实现（按 PET_APP_ENV 选覆盖文件）
│       ├── stage-test.sh              # 测试阶段实现（unit | smoke | all）
│       ├── stage-release.sh           # 发布准备实现（demo/ci/staging 三份 compose 校验）
│       ├── backend-healthcheck.sh     # 后端存活探测（compose healthcheck 调用）
│       └── frontend-healthcheck.sh    # 前端存活探测（compose healthcheck 调用）
├── backend/
│   ├── Dockerfile                # node:20-slim，npm ci --omit=dev，npmmirror
│   └── src/app.js                # GET /health 存活端点
└── frontend/
    ├── Dockerfile                # 多阶段：node:20-alpine 构建 -> nginx:alpine 运行
    └── nginx.conf                # location = /health
```

`.ci/*.yml` 是阶段的**声明式描述**，`.ci/scripts/stage-*.sh` 是对应**实现**。
`run-pipeline.sh` 只负责按参数调度阶段脚本，不包含具体命令。

---

## 2. 环境变量约定

后续轮次按以下名字引用，请勿改名：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `PET_APP_ENV` | `demo` | 运行形态：`demo` \| `ci` \| `staging` |
| `PET_API_PUBLISH_PORT` | `8731` | 后端发布到宿主机的端口 |
| `PET_WEB_PUBLISH_PORT` | `3731` | 前端发布到宿主机的端口 |
| `PET_DB_PUBLISH_PORT` | `5731` | MongoDB 发布到宿主机的端口 |
| `PET_VITE_API_URL` | `/api`（staging 覆盖为 `http://localhost:8731`） | 前端构建期注入的 API 前缀 |
| `PET_COMPOSE_PROJECT_NAME` | `pet-adoption` | compose project 名，也用于镜像/容器命名 |
| `PET_IMAGE_TAG` | `${PET_APP_ENV}-latest` | release 阶段给镜像打的标签 |
| `PET_ARTIFACT_DIR` | `.ci/.artifacts` | 产物清单输出目录（已被 .gitignore） |
| `PET_TEST_KIND` | `all` | test 阶段门禁选择：`unit` \| `smoke` \| `all` |
| `PET_NODE_VERSION` | `20` | unit 门禁要求的 CI job/host Node 主版本 |
| `PET_COVERAGE_GATE` | `false` | 设为 `true` 时 unit 门禁额外跑 `jest --coverage` 并校验 `coverage/lcov.info` 存在（不设阈值） |
| `PET_RELEASE_ENV` | `staging` | release 的 `health_gate` 目标环境（demo\|ci\|staging） |
| `PET_OUT_DIR` | `.ci/out` | release 产物清单输出目录（已被 .gitignore） |
| `PET_JWT_SECRET` | `pet-adoption-docker-secret` | 后端 JWT 密钥（staging 用私有 env 覆盖） |
| `PET_MONGODB_URI` | `mongodb://db:27017/pet_adoption` | 后端 Mongo 连接串 |
| `PET_SEED_DEMO` | `true` | 是否播种 demo 用户 |
| `PET_UPLOAD_DIR` | `/app/uploads` | 后端上传目录 |

容器内部监听端口保持现网约定：后端 `8731`、前端 Nginx `80`、Mongo `27017`。

---

## 3. 环境矩阵

| 形态 | compose 文件 | `PET_APP_ENV` | `PET_VITE_API_URL` | 真实 Mongo | 宿主机端口 | 适用门禁 |
| --- | --- | --- | --- | --- | --- | --- |
| demo | `docker-compose.yml` | `demo` | `/api`（同源反代） | 是 | 3731/8731/5731 | smoke / 本地验证 |
| ci | `-f docker-compose.yml -f docker-compose.ci.yml` | `ci` | `/api` | 是（但不发布端口） | 不暴露 | unit + smoke |
| staging | `--env-file .ci/config/env.staging -f docker-compose.yml -f docker-compose.staging.yml` | `staging` | `http://localhost:8731`（跨域直连） | 是 | 3731/8731/5731 | smoke / 准生产验证 |

> 单测（`unit`）始终使用 `mongodb-memory-server`，**不连接**任何形态下的真实 Mongo，
> 因此在三种形态下都可独立运行。

### 3.1 demo（本地一键演示）

```bash
docker compose up --build -d

docker compose ps
curl http://localhost:8731/health        # {"status":"ok",...}
curl http://localhost:3731/health        # ok
curl http://localhost:3731/api/health    # 经 Nginx 反代
```

### 3.2 ci（CI 机器 / 集成验证）

```bash
# 不暴露宿主机端口，仅内部网络互通
PET_APP_ENV=ci docker compose \
  -f docker-compose.yml -f docker-compose.ci.yml up --build -d
```

CI 上单测不需要起 Mongo 容器：

```bash
sh .ci/scripts/stage-test.sh unit
```

### 3.3 staging（准生产验证）

staging 与 demo/ci 的关键差异是前端构建参数 `PET_VITE_API_URL` 默认为
**`http://localhost:8731`（绝对地址）**，而不是 demo 的 `/api`。

- **为什么不同**：demo 下浏览器只访问 `http://localhost:3731`，Nginx 把 `/api/*`
  反代到后端，属于**同源**访问，因此前端用相对前缀 `/api` 即可。staging 要验证
  准生产的**跨域**形态——浏览器从前端 origin 直接访问后端 API origin（8731），
  这会真正走到后端的 CORS 白名单（`app.js` 中已允许 `localhost:3731`），与
  “前后端分属不同源”的部署形态一致。
- staging 使用真实 Mongo（db 服务），用于集成/冒烟，而非内存库。
- 重启/启动策略沿用 base：`restart: unless-stopped`，`depends_on` 带
  `condition: service_healthy`（后端等 db 健康、前端等后端健康）。不使用
  Swarm/K8s 的 `deploy.resources`。

准备私有 env 并启动（详见 §7）：

```bash
cp .ci/config/env.staging.example .ci/config/env.staging
# 编辑 .ci/config/env.staging 替换假值

docker compose --env-file .ci/config/env.staging \
  -f docker-compose.yml -f docker-compose.staging.yml up -d --build
```

---

## 4. 流水线与门禁

### 4.1 总入口参数

```bash
sh .ci/scripts/run-pipeline.sh [stage ...]
```

- 不带参数：`build test release`（完整流水线）
- `build`：只构建
- `test`：只测试（含 unit + smoke；用 `PET_TEST_KIND` 选子门禁）
- `build test`：构建后测试（不发布）
- `build release`：构建后发布准备（跳过测试）

test 子门禁：

```bash
PET_TEST_KIND=unit  sh .ci/scripts/run-pipeline.sh test   # 只跑单测
PET_TEST_KIND=smoke sh .ci/scripts/run-pipeline.sh test   # 只跑冒烟
PET_TEST_KIND=all   sh .ci/scripts/run-pipeline.sh test   # 单测+冒烟（默认）
```

也可直接调用阶段脚本：

```bash
sh .ci/scripts/stage-build.sh
sh .ci/scripts/stage-test.sh unit
sh .ci/scripts/stage-test.sh smoke
sh .ci/scripts/stage-release.sh
```

### 4.2 unit 门禁（在 `.ci/test.yml` 的 `unit` 步骤声明）

- 运行环境：CI job / 主机，**Node 20**（`PET_NODE_VERSION`），需有 npm。
- 工作目录与步骤：
  - `backend/`：`npm ci --registry=https://registry.npmmirror.com` → `npm run lint` → `npm test`
  - `frontend/`：`npm ci --registry=https://registry.npmmirror.com` → `npm run lint`
- 数据库：`backend/tests/setup.js` 启动 `mongodb-memory-server`，**不连接** compose 的 db 服务，无端口抢占、无数据污染。
- 不需要 Docker 守护进程。

### 4.3 smoke 门禁（在 `.ci/test.yml` 的 `smoke` 步骤声明）

- 运行环境：需要 Docker，按 `PET_APP_ENV` 选择 compose 覆盖（ci 或 staging）。
- 步骤：`docker compose up -d --build --wait`（等待 healthcheck 全部 healthy），然后
  - `docker compose exec -T backend sh /ci/scripts/backend-healthcheck.sh`
  - `docker compose exec -T frontend sh /ci/scripts/frontend-healthcheck.sh`
- smoke 复用第 1 轮的外置健康检查脚本，不把 curl 内联进 YAML。
- 冒烟结束后栈保持运行，便于排查；用对应的 `docker compose ... down` 清理。

### 4.4 coverage 门禁（可选，默认关闭）

- 开关：`PET_COVERAGE_GATE=true`（默认 `false`）。
- 行为：在 backend 的 `npm test` 之后执行 `npm run test:coverage`（即 `jest --coverage`），
  并断言 `backend/coverage/lcov.info` 文件存在。
- **只检查报告存在性，不设覆盖率阈值**，避免为刷阈值而改业务测试。前端无测试运行器，不参与此门禁。
- backend `package.json` 新增了 `test:coverage` 脚本，未改动任何业务测试。

---

## 5. release 发布准备门禁

release 阶段在 [.ci/release.yml](../../.ci/release.yml) 声明，实现在
[stage-release.sh](../../.ci/scripts/stage-release.sh)，包含三个可独立运行的门禁，
**不推送镜像、不做 git 操作**。总入口 `run-pipeline.sh release` 会依次跑完三者。

| 门禁 | 作用 | 失败含义 |
| --- | --- | --- |
| `image_exists` | 确认 `<project>-backend:latest`、`<project>-frontend:latest` 已构建，打标签为 `:<PET_IMAGE_TAG>` 并复验 | 镜像没构建，需先跑 build |
| `health_gate` | 对 `PET_RELEASE_ENV`（默认 staging）起栈 `up -d --wait`，在容器内 exec 两个 healthcheck 脚本 | 目标环境不健康，阻止发布 |
| `artifact_manifest` | 校验三份 compose 配置，由模板渲染 `.ci/out/release-manifest.md` | compose 配置非法或模板缺失 |

**镜像 tag 规则（沿用第 1 轮，未迁移）**：

```
repository : <PET_COMPOSE_PROJECT_NAME>-<service>   # pet-adoption-backend
floating   : latest
release    : <PET_IMAGE_TAG>                        # 默认 <PET_APP_ENV>-latest
```

完整引用如 `pet-adoption-backend:staging-latest`。env 名在 **tag** 中，而非 repository 中。
本轮未切换到 `<project>-<env>-<service>` 形式；若后续要迁移需单独一轮并重打标签。

单独运行某个门禁：

```bash
sh .ci/scripts/stage-release.sh image_exists
sh .ci/scripts/stage-release.sh health_gate
PET_RELEASE_ENV=ci sh .ci/scripts/stage-release.sh health_gate
sh .ci/scripts/stage-release.sh artifact_manifest
sh .ci/scripts/stage-release.sh all          # 三门禁依次执行
```

发布清单模板见 [release-manifest.example.md](release-manifest.example.md)，运行时渲染到
`.ci/out/release-manifest.md`（已 gitignore）。

---

## 6. 构建参数透传链路（VITE_API_URL）

第 1 轮已建立完整链路，第 2 轮经核查无缺口，并补了 staging 默认值与文档固化：

```
PET_VITE_API_URL (host env / --env-file)
        │  docker-compose.yml / .staging.yml 变量插值
        ▼
build.args.VITE_API_URL
        │  frontend/Dockerfile
        ▼
ARG VITE_API_URL=/api  →  ENV VITE_API_URL=$VITE_API_URL  →  npm run build
        │  Vite 读取 process.env.VITE_API_URL
        ▼
import.meta.env.VITE_API_URL   (frontend/src/services/*.js)
```

- demo/ci 默认 `/api`（同源经 Nginx 反代）。
- staging 覆盖默认值为 `http://localhost:8731`（跨域直连），见
  [docker-compose.staging.yml](../../docker-compose.staging.yml)。
- 任何形态都可用 `PET_VITE_API_URL=https://api.example.com` 在调用方显式覆盖。
- Dockerfile 内 `ARG` 默认值 `/api` 仅在 compose 未传参时兜底，不影响上述链路。

---

## 7. 镜像与依赖纪律

- **基础镜像**（DaoCloud 加速）：后端 `docker.m.daocloud.io/library/node:20-slim`；
  前端构建 `docker.m.daocloud.io/library/node:20-alpine`；前端运行
  `docker.m.daocloud.io/library/nginx:alpine`；数据库 `docker.m.daocloud.io/library/mongo:7`。
- **依赖安装**：Dockerfile 与 CI 脚本一律 `npm ci`，禁止 `npm install`；
  本地开发文档可保留 `npm install`，镜像构建 / CI 路径不允许。
- **npm registry**：统一 `https://registry.npmmirror.com`。
- **锁文件**：`backend/package-lock.json`、`frontend/package-lock.json` 必须提交，
  构建前 `stage-build.sh` 校验，缺失即失败。
- **不引入** nx / turborepo / lerna / pnpm-workspace 等编排工具；编排仅靠
  仓库内 YAML + shell + docker compose。
- 镜像命名：`<PET_COMPOSE_PROJECT_NAME>-backend:latest`、
  `<PET_COMPOSE_PROJECT_NAME>-frontend:latest`，release 阶段额外打 `PET_IMAGE_TAG`。

---

## 8. 健康检查如何被调用

健康检查逻辑从启动命令中剥离，由脚本实现；compose 的 `healthcheck.test` 只调用脚本：

```yaml
healthcheck:
  test: ["CMD", "sh", "/ci/scripts/backend-healthcheck.sh"]
```

脚本通过只读 bind mount 注入：

```yaml
volumes:
  - ./.ci/scripts:/ci/scripts:ro
```

- [backend-healthcheck.sh](../.ci/scripts/backend-healthcheck.sh)：用镜像内 `node`
  请求 `GET http://127.0.0.1:8731/health`，可配置 `HEALTH_HOST/PORT/PATH/RETRIES/INTERVAL`。
- [frontend-healthcheck.sh](../.ci/scripts/frontend-healthcheck.sh)：用 nginx:alpine
  自带的 busybox `wget` 请求 `http://127.0.0.1:80/health`。

后端 `/health` 是 liveness（不查库）；Nginx `/health` 直接返回 `200 ok`。
smoke 门禁在容器内 `exec` 这两个脚本，确认整栈可达。

---

## 9. staging 密钥与配置

staging 的敏感配置通过 `--env-file` 注入 compose 插值，不写入镜像：

1. 从示例生成本地私有文件（该文件已被 `.gitignore` 忽略，只有示例入库）：

   ```bash
   cp .ci/config/env.staging.example .ci/config/env.staging
   ```

2. 编辑 `.ci/config/env.staging`，把假值替换为真实 staging 值：
   - `PET_JWT_SECRET`：JWT 签名密钥
   - `PET_MONGODB_URI`：Mongo 连接串（默认指向 compose 的 db 服务）
   - `PET_SEED_DEMO`、`PET_UPLOAD_DIR`、`PET_VITE_API_URL` 等
   - 全部使用大写蛇形命名

3. 启动时显式加载：

   ```bash
   docker compose --env-file .ci/config/env.staging \
     -f docker-compose.yml -f docker-compose.staging.yml up -d --build
   ```

示例文件 [env.staging.example](../.ci/config/env.staging.example) 中的值均为假数据，
可安全提交；真实 `env.staging` 不要提交。本轮不接任何真云密钥。

---

## 10. 常见失败排查

| 现象 | 原因 / 处理 |
| --- | --- |
| 构建失败 `lockfile missing` | 本地没生成或没提交 `package-lock.json`。在对应目录 `npm install` 后提交锁文件。 |
| `npm ci` 报 `EUSAGE` / 依赖不匹配 | `package.json` 与锁文件不同步。本地 `npm install` 更新后提交，不要在容器里 `npm install`。 |
| npm registry 超时 | 确认 registry 为 `https://registry.npmmirror.com`；CI 网络受限时检查代理。 |
| 端口占用 `port is already allocated` | 用 `PET_*_PUBLISH_PORT` 改端口，或 `docker compose down` 释放。默认 3731/8731/5731。 |
| healthcheck 一直 `starting` / `unhealthy` | ① 后端没连上 Mongo：`docker compose logs backend`；② 脚本 CRLF 污染：确认 `.gitattributes` 生效；③ start_period 太短，按需调大。 |
| healthcheck 假阳性 | `/health` 是 liveness，不代表数据库可用；readiness 需另加带 Mongo ping 的端点。 |
| CI 单测去连真实 Mongo 端口冲突 | `unit` 走 `tests/setup.js` 的 `mongodb-memory-server`，不要把 `MONGODB_URI` 指到 db 容器。 |
| `docker compose ... config` 报标签错 | `!override []` 需 Compose v2.24+（随 Docker Desktop 提供）。 |
| staging 前端跨域请求失败 | 确认后端 CORS 白名单包含前端 origin（staging 默认前端 3731 → 后端 8731，已在 `app.js` 允许）。 |
| staging 启动找不到私有 env | 必须加 `--env-file .ci/config/env.staging`；文件不存在时 compose 会用默认值（demo 密钥），不会自动读取。 |
| `docker compose up --wait` 超时 | 有容器未在 start_period 内变 healthy；看 `docker compose ps` 与 `docker compose logs <svc>`。 |
| release `image_exists` 失败 | 镜像未构建或 `PET_COMPOSE_PROJECT_NAME` 与 build 时不一致；先跑 build 阶段，并确保 build/release 用同一 project 名。 |
| release `health_gate` 失败 | 目标环境（默认 staging）不健康；查看 `docker compose ps`、`docker compose logs`，或单独 `sh .ci/scripts/stage-release.sh health_gate` 复现。 |
| coverage 门禁报 `lcov.info was not produced` | `jest --coverage` 未生成报告；确认 backend 测试能跑通，或检查是否误删 coverage 目录；该门禁默认关闭，用 `PET_COVERAGE_GATE=true` 开启。 |
