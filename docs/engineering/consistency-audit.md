# 跨轮一致性审计（Consistency Audit）

本审计在第 3 轮发布门禁落地前执行，逐条回溯第 1、2 轮确立的工程约定，检查现状是否自相矛盾。
原则：**优先改工程文件使其回到约定，而不是改文档迁就错误实现。**

审计方法：逐文件读取 + 全仓 grep（`npm install`、内联 `curl`/`wget`、端口、变量名）+
`docker compose config` 合并校验。

---

## 探针 A：阶段职责是否仍分离？（来自第 1 轮）

**约定**：`.ci/build.yml`、`.ci/test.yml`、`.ci/release.yml`、`.ci/pipeline.yml`
职责边界清晰；总入口只调度，不得把阶段具体命令回迁。

**现状**：

| 文件 | 职责 |
| --- | --- |
| [.ci/pipeline.yml](../../.ci/pipeline.yml) | 仅声明环境、阶段顺序与 `uses:` 引用，无具体命令 |
| [.ci/build.yml](../../.ci/build.yml) | 仅声明 build 阶段入口 `stage-build.sh` |
| [.ci/test.yml](../../.ci/test.yml) | 声明 `unit` / `smoke` 两个步骤，分别调 `stage-test.sh unit|smoke` |
| [.ci/release.yml](../../.ci/release.yml) | 声明 `image_exists` / `health_gate` / `artifact_manifest` 三个步骤，分别调 `stage-release.sh <gate>` |
| [.ci/scripts/run-pipeline.sh](../../.ci/scripts/run-pipeline.sh) | 仅 `case` 分发到 `stage-*.sh`，无任何 npm/docker/compose 具体命令 |

**结论**：✅ **一致**。第 3 轮新增的 release 三门禁继续遵循"YAML 声明 + shell 实现 +
总入口只调度"模式，未把命令回迁到 `pipeline.yml` 或 `run-pipeline.sh`。

---

## 探针 B：healthcheck 是否仍由外置脚本承担？（来自第 1 轮）

**约定**：存活探测在 `.ci/scripts/*-healthcheck.sh`，compose `healthcheck.test`
只调用脚本，禁止内联 `curl` 长命令。

**现状**：

- [docker-compose.yml](../../docker-compose.yml#L36-L41) backend：`test: ["CMD","sh","/ci/scripts/backend-healthcheck.sh"]`
- [docker-compose.yml](../../docker-compose.yml#L60-L65) frontend：`test: ["CMD","sh","/ci/scripts/frontend-healthcheck.sh"]`
- 脚本通过 `.ci/scripts:/ci/scripts:ro` 只读挂载注入。
- [docker-compose.ci.yml](../../docker-compose.ci.yml) 与 [docker-compose.staging.yml](../../docker-compose.staging.yml) 均**继承**该 healthcheck，未重写为内联命令。
- 全仓 grep `curl ` / `wget ` 在 compose/Dockerfile 中无命中；`wget` 仅存在于
  [frontend-healthcheck.sh](../../.ci/scripts/frontend-healthcheck.sh)（外置脚本本身，允许）。

**结论**：✅ **一致**。release 的 `health_gate` 也通过 `docker compose exec ... sh /ci/scripts/*-healthcheck.sh`
复用同一对脚本，没有另写探测逻辑。

---

## 探针 C：Docker/CI 是否仍全部 `npm ci` + npmmirror？（来自第 1 轮）

**约定**：镜像构建与 CI 脚本只用 `npm ci`，registry 统一 `https://registry.npmmirror.com`，
禁止 `npm install`。

**现状**：

| 位置 | 命令 | registry |
| --- | --- | --- |
| [backend/Dockerfile](../../backend/Dockerfile#L6) | `npm ci --omit=dev` | `npm config set registry https://registry.npmmirror.com` |
| [frontend/Dockerfile](../../frontend/Dockerfile#L4) | `npm ci` | 同上 |
| [.ci/scripts/stage-test.sh](../../.ci/scripts/stage-test.sh) | `npm ci --registry=...` | `NPM_REGISTRY=https://registry.npmmirror.com` |
| [.ci/scripts/stage-build.sh](../../.ci/scripts/stage-build.sh) | 不直接装依赖，调用 compose build（走 Dockerfile 的 `npm ci`） | 由 Dockerfile 保证 |

全仓 grep `npm install` 在 `Dockerfile`、`.ci/**/*.sh`、`*.yml` 中**零命中**
（仅 README 本地开发说明中保留 `npm install`，符合"本地文档可保留"的约定）。

**结论**：✅ **一致**。

---

## 探针 D：端口 3731/8731/5731 与 `PET_*_PUBLISH_PORT` 是否对齐？（来自第 1 轮）

**约定**：前端 3731、后端 8731、数据库 5731；容器内监听后端 8731 / Nginx 80 / Mongo 27017。

**现状**：

- [docker-compose.yml](../../docker-compose.yml#L7) db：`${PET_DB_PUBLISH_PORT:-5731}:27017`
- [docker-compose.yml](../../docker-compose.yml#L32) backend：`${PET_API_PUBLISH_PORT:-8731}:8731`
- [docker-compose.yml](../../docker-compose.yml#L57) frontend：`${PET_WEB_PUBLISH_PORT:-3731}:80`
- ci overlay 用 `!override []` 清空宿主机端口，容器内端口不变。
- staging overlay 不重定义端口，继承 base。

**结论**：✅ **一致**。

---

## 探针 E：`PET_APP_ENV` 是否支持 demo/ci/staging 三值？（来自第 2 轮）

**约定**：三值齐备，三份 compose（或等价覆盖）在 playbook 矩阵表可查。

**现状**：

- [.ci/scripts/stage-build.sh](../../.ci/scripts/stage-build.sh#L34-L42) `case` 支持 demo/ci/staging。
- [.ci/scripts/stage-test.sh](../../.ci/scripts/stage-test.sh#L61-L72) `compose_files` 支持三值。
- [.ci/scripts/stage-release.sh](../../.ci/scripts/stage-release.sh#L41-L59) `compose_files_for` 支持三值。
- 三份文件存在：`docker-compose.yml`、`docker-compose.ci.yml`、`docker-compose.staging.yml`。
- [ci-docker-playbook.md](ci-docker-playbook.md) §3 环境矩阵表列出三形态的 compose 文件、
  `PET_APP_ENV`、`PET_VITE_API_URL`、是否真实 Mongo、端口、门禁。
- 三份合并配置均通过 `docker compose config -q`。

**结论**：✅ **一致**。

---

## 探针 F：demo 与 staging 的 `PET_VITE_API_URL` 差异是否在文档与 build args 链路同时存在？（来自第 2 轮）

**约定**：demo/ci 用 `/api`（同源反代），staging 用 `http://localhost:8731`（跨域直连）；
链路 `PET_VITE_API_URL → build.args → Dockerfile ARG/ENV → import.meta.env`。

**现状**：

- base compose [docker-compose.yml#L52](../../docker-compose.yml#L52)：`VITE_API_URL: ${PET_VITE_API_URL:-/api}`。
- staging overlay [docker-compose.staging.yml#L54](../../docker-compose.staging.yml#L54)：
  `VITE_API_URL: ${PET_VITE_API_URL:-http://localhost:8731}`。
- [frontend/Dockerfile#L6-L7](../../frontend/Dockerfile#L6-L7)：`ARG VITE_API_URL=/api` → `ENV VITE_API_URL=$VITE_API_URL`。
- 前端服务 `src/services/*.js` 通过 `import.meta.env.VITE_API_URL` 消费。
- 实测：staging 构建产物含 `http://localhost:8731/auth`、`/pets`；demo 产物含 `/api/auth`、`/api/pets`。
- playbook §3 矩阵表与 §5 透传链路图均记录该差异。

**结论**：✅ **一致**。第 1 轮链路本就完整，第 3 轮未改动该链路，仅补充 release manifest 模板记录。

---

## 探针 G：`.ci/config/env.staging.example` 是否存在且键名大写蛇形？（来自第 2 轮）

**约定**：示例文件存在，键名全大写蛇形，值为假数据。

**现状**：[.ci/config/env.staging.example](../../.ci/config/env.staging.example)
存在，键名 `PET_APP_ENV`、`PET_COMPOSE_PROJECT_NAME`、`PET_API_PUBLISH_PORT`、
`PET_WEB_PUBLISH_PORT`、`PET_DB_PUBLISH_PORT`、`PET_VITE_API_URL`、`PET_JWT_SECRET`、
`PET_MONGODB_URI`、`PET_SEED_DEMO`、`PET_UPLOAD_DIR`、`NODE_ENV`，全部大写蛇形，
密钥标注 `fake-staging-jwt-secret-replace-me`。真实 `env.staging` 已被 `.gitignore` 忽略。

**结论**：✅ **一致**。

---

## 镜像 tag 规则的决策说明（非冲突，但需显式记录）

题目示例给出 `${PET_COMPOSE_PROJECT_NAME}-${PET_APP_ENV}-...` 形式。第 1、2 轮实际确立并在
代码中使用的规则是：

```
<repository>: <PET_COMPOSE_PROJECT_NAME>-<service>     # pet-adoption-backend
<floating>  : latest
<release>   : <PET_IMAGE_TAG>   # 默认 <PET_APP_ENV>-latest，如 staging-latest
```

即完整引用为 `pet-adoption-backend:staging-latest`（env 在 tag 中），而非
`pet-adoption-staging-backend:latest`（env 在 repository 中）。

按题目"不要突然换一套 tag 语法而不说明迁移"的要求，**第 3 轮保留第 1/2 轮既有规则不做迁移**，
并在 [.ci/release.yml](../../.ci/release.yml)、[stage-release.sh](../../.ci/scripts/stage-release.sh)、
[release-manifest.example.md](release-manifest.example.md) 与本审计中显式声明该规则。
若后续轮次要切换到 `<project>-<env>-<service>` 形式，需单独一轮做迁移并提供重打标签脚本。

---

## 本轮修复项

审计未发现需要"改工程文件回到约定"的硬冲突。本轮新增内容均遵循既有约定：

1. release 三门禁（`image_exists` / `health_gate` / `artifact_manifest`）继续放在
   `.ci/release.yml` + `stage-release.sh`，未塞回总入口。
2. coverage 门禁挂在 test 阶段（`PET_COVERAGE_GATE`），未糊进 release。
3. 未引入新基础镜像、新 npm 依赖、K8s/Helm/Terraform 或 monorepo 工具。
4. 未做任何 git 操作，未推送镜像。

一个**使用注意**（非代码冲突）：`env.staging.example` 中
`PET_COMPOSE_PROJECT_NAME=pet-adoption-staging`，若用该 env 文件起 staging 栈，
镜像名会是 `pet-adoption-staging-backend:latest`；build 与 release 必须使用**同一个**
`PET_COMPOSE_PROJECT_NAME`，否则 `image_exists` 找不到镜像。playbook §3.3 与 §8 已说明
需带 `--env-file` 启动。

---

## 回溯校验清单

| 轮次 | 约定摘要 | 本轮核查结果 | 证据路径 |
| --- | --- | --- | --- |
| R1 | build/test/release/pipeline 四文件职责分离，总入口只调度 | ✅ 通过 | [.ci/scripts/run-pipeline.sh](../../.ci/scripts/run-pipeline.sh#L36-L52) |
| R1 | healthcheck 由 `.ci/scripts/*-healthcheck.sh` 外置承担 | ✅ 通过 | [docker-compose.yml](../../docker-compose.yml#L36-L41) |
| R1 | compose 中无内联 curl 长命令 | ✅ 通过 | 全仓 grep，仅外置脚本含 wget/node |
| R1 | Docker/CI 全部 `npm ci` + `registry.npmmirror.com` | ✅ 通过 | [backend/Dockerfile](../../backend/Dockerfile#L6)、[frontend/Dockerfile](../../frontend/Dockerfile#L4)、[stage-test.sh](../../.ci/scripts/stage-test.sh#L35) |
| R1 | 无 `npm install` 回归 | ✅ 通过 | grep `npm install` 在 Docker/CI 路径零命中 |
| R1 | 端口 3731/8731/5731 与 `PET_*_PUBLISH_PORT` 对齐 | ✅ 通过 | [docker-compose.yml](../../docker-compose.yml#L7) |
| R1 | 基础镜像 node:20-slim/alpine + nginx:alpine + mongo:7（DaoCloud） | ✅ 通过 | 两份 Dockerfile + docker-compose.yml |
| R2 | `PET_APP_ENV` 支持 demo/ci/staging | ✅ 通过 | [stage-build.sh](../../.ci/scripts/stage-build.sh#L34-L42)、[stage-test.sh](../../.ci/scripts/stage-test.sh#L47-L60)、[stage-release.sh](../../.ci/scripts/stage-release.sh#L44-L57) |
| R2 | 三份 compose 覆盖文件存在且可合并 | ✅ 通过 | `docker compose config -q` 三种合并均通过 |
| R2 | demo `/api` vs staging `http://localhost:8731` 在文档与 build args 双在 | ✅ 通过 | [docker-compose.staging.yml#L54](../../docker-compose.staging.yml#L54)、playbook §3/§5 |
| R2 | `PET_VITE_API_URL` 透传链路完整 | ✅ 通过 | Dockerfile ARG/ENV → `import.meta.env`（实测产物验证） |
| R2 | `.ci/config/env.staging.example` 存在且大写蛇形 | ✅ 通过 | [.ci/config/env.staging.example](../../.ci/config/env.staging.example) |
| R3 | release 三门禁仅在 `.ci/release.yml` + `stage-release.sh` | ✅ 通过 | [.ci/release.yml](../../.ci/release.yml)、[stage-release.sh](../../.ci/scripts/stage-release.sh) |
| R3 | coverage 门禁挂在 test 阶段，默认关闭可开启 | ✅ 通过 | [.ci/test.yml](../../.ci/test.yml#L18)、[stage-test.sh](../../.ci/scripts/stage-test.sh#L43-L53) |
| R3 | tag 规则沿用 R1/R2，未擅自换语法 | ✅ 通过 | [stage-release.sh#L18-L23](../../.ci/scripts/stage-release.sh#L18-L23) |
