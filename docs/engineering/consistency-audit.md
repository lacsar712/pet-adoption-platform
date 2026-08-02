# 跨轮一致性审计（consistency-audit）

审计时间：第 3 轮。审计范围：第 1、2 轮定下的工程约定是否仍然自洽；
发现冲突时优先改工程文件回归约定，而非改文档迁就实现。

## 探针逐项核查

### 探针 A（第 1 轮）：阶段职责分离

- **现状**：`.ci/build.yml`（构建）、`.ci/test.yml`（unit/smoke/coverage 门禁）、
  `.ci/release.yml`（validate/image_exists/health_gate/artifact_manifest 门禁）、
  `.ci/pipeline.yml`（仅声明 include 顺序）；可执行入口 `pipeline.sh` 只循环调用
  `run-stage.sh`，不含任何阶段命令。
- **核查方法**：通读四份 YAML 与两份调度脚本；`pipeline.yml`/`pipeline.sh`
  中无 `docker compose build`、`npm`、`docker tag` 等阶段命令。
- **结论**：✅ 一致，无命令回迁。

### 探针 B（第 1 轮）：healthcheck 外置

- **现状**：后端/前端探测仍由 `.ci/scripts/backend-healthcheck.sh` /
  `frontend-healthcheck.sh` 承担；`docker-compose.yml` 通过只读挂载
  `./.ci/scripts:/healthcheck:ro` 调用脚本，ci/staging 覆盖文件继承该挂接。
- **核查方法**：`grep -r "curl\|wget" *.yml` 仅命中注释（无内联探测命令）。
- **唯一例外（有意保留）**：`db` 服务的 healthcheck 使用 `mongosh --eval
  db.adminCommand('ping')` 内联——这是 Mongo 镜像自带客户端的单行命令，
  不属于"curl 长命令"，且第 1 轮即如此定义，不属于回归。
- **结论**：✅ 一致。

### 探针 C（第 1 轮）：npm ci + npmmirror

- **现状**：`backend/Dockerfile`、`frontend/Dockerfile` 均为
  `npm config set registry https://registry.npmmirror.com && npm ci`；
  `.ci/test.yml` 各门禁使用 `npm --prefix backend ci --registry=https://registry.npmmirror.com`。
- **核查方法**：全仓 grep `npm install`，仅命中文档说明与 README 的本地开发
  指引（约定明确允许），Docker/CI 路径零命中。
- **结论**：✅ 一致，无回归。

### 探针 D（第 1 轮）：端口约定

- **现状**：`${PET_WEB_PUBLISH_PORT:-3731}`、`${PET_API_PUBLISH_PORT:-8731}`、
  `${PET_DB_PUBLISH_PORT:-5731}` 在 `docker-compose.yml` 与 healthcheck 调用、
  playbook 中一致；CI 叠加文件用 `!reset []` 移除 db 发布端口（有意设计）。
- **核查方法**：grep `3731|8731|5731` 逐条比对；compose config 渲染结果
  （第 1、2 轮验证）与默认值一致。
- **结论**：✅ 一致。

### 探针 E（第 2 轮）：PET_APP_ENV 三值与 compose 矩阵

- **现状**：`PET_APP_ENV` 支持 `demo`（根文件默认）/ `ci`（ci 覆盖）/
  `staging`（staging 覆盖）；三份 compose 文件均在 playbook 第 3 节
  「环境矩阵」表中列出，含验证命令。
- **结论**：✅ 一致。

### 探针 F（第 2 轮）：PET_VITE_API_URL 的 demo/staging 差异

- **现状**：文档侧——playbook 第 3 节矩阵表 + 差异论证段落；链路侧——
  `docker-compose.yml` 默认 `/api`、`docker-compose.staging.yml` 默认
  `http://localhost:8731`，两者都经 `build.args.VITE_API_URL` → Dockerfile
  `ARG/ENV` → Vite 注入。
- **结论**：✅ 文档与链路同时存在该差异。

### 探针 G（第 2 轮）：env.staging.example

- **现状**：`.ci/config/env.staging.example` 存在，键名全部大写蛇形
  （`PET_APP_ENV`、`PET_VITE_API_URL`、`JWT_SECRET`、`MONGODB_URI`、
  `SEED_DEMO`、`UPLOAD_DIR` 等），示例值均为假数据。
- **结论**：✅ 一致。

### 探针 H（第 3 轮自查）：release 产物命名

- **发现的冲突**：第 1 轮 `release.yml` 的发布 tag 为
  `pet-adoption-backend:${PET_IMAGE_TAG:-ci-local}`，tag 中不含环境名，
  多环境矩阵下会互相覆盖；同时第 1 轮把归档清单写成仓库根目录的
  `release-manifest.txt`，与"产物归档应有固定目录"的演进方向不符。
- **修复（本轮已改工程文件）**：
  1. tag 规则定版为 `${PET_COMPOSE_PROJECT_NAME}-<service>:${PET_APP_ENV}-${PET_IMAGE_TAG}`
     （例：`pet-adoption-backend:staging-ci-local`），兼容变量全部沿用前两轮命名，
     未引入新变量族；
  2. 归档清单迁移为 `.ci/out/release-manifest.md`（由
     `.ci/scripts/release-manifest.sh` 生成），根目录 `release-manifest.txt`
     生成步骤已从 `release.yml` 移除。
- **迁移说明**：旧 tag（`...:ci-local`）与旧清单文件不再产生；若本地存在
  历史产物，可安全删除，不影响任何阶段命令。

## 回溯校验清单

| 轮次 | 约定摘要 | 本轮核查结果 | 证据路径 |
| --- | --- | --- | --- |
| 1 | `.ci/` 四文件职责分离，总入口只调度 | 通过 | `.ci/pipeline.yml`、`.ci/scripts/pipeline.sh`、`.ci/scripts/run-stage.sh` |
| 1 | healthcheck 外置脚本，禁止内联 curl | 通过（db 用 mongosh 为有意例外） | `.ci/scripts/*-healthcheck.sh`、`docker-compose.yml` |
| 1 | Docker/CI 全部 `npm ci` + npmmirror | 通过 | `backend/Dockerfile`、`frontend/Dockerfile`、`.ci/test.yml` |
| 1 | 端口 3731/8731/5731 + `PET_*_PUBLISH_PORT` | 通过 | `docker-compose.yml`、playbook 第 2 节 |
| 1 | 发布 tag/清单规则 | **已修复**（tag 加环境段、清单迁至 `.ci/out/`） | `.ci/release.yml`、`.ci/scripts/release-manifest.sh` |
| 2 | `PET_APP_ENV` = demo/ci/staging 三值 | 通过 | 三份 compose 文件、playbook 第 3 节 |
| 2 | `PET_VITE_API_URL` demo `/api` vs staging 直连 | 通过（文档与 build args 链路一致） | `docker-compose.staging.yml`、playbook 第 3/5 节 |
| 2 | `env.staging.example` 大写蛇形假数据 | 通过 | `.ci/config/env.staging.example` |
| 2 | test 阶段门禁化（unit/smoke） | 通过（本轮扩展 coverage 可选门禁，机制不变） | `.ci/test.yml` |
| 3 | release 门禁（validate/image_exists/health_gate/artifact_manifest） | 通过（本轮新增，默认目标环境 staging） | `.ci/release.yml` |
