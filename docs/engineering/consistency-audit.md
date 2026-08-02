# Cross-Round Consistency Audit (Round 3)

本文件对照第 1 / 第 2 轮的「早期约定探针」逐条核查现状，记录取值、是否一致、
以及不一致时的修复动作。审计原则：**发现冲突优先改工程文件回到约定，而非改文档
迁就错误实现。**

审计时间基准：第 3 轮。核查方式：静态阅读 + `docker compose config` + grep。

---

## 探针逐条核查

### 探针 A（第 1 轮）— 阶段职责分离，命令未回迁总入口
- 现状路径：`.ci/build.yml`、`.ci/test.yml`、`.ci/release.yml` 各自声明单一阶段；
  `.ci/pipeline.yml` 仅用 `stages: [ {name, include} ]` 编排；
  `.ci/scripts/pipeline.sh` 只 `for stage in ...; do run-stage.sh ${stage}; done`。
- 具体命令集中在 `.ci/scripts/run-stage.sh` 的 `stage_build/stage_test/stage_release`。
- 是否一致：**一致（通过）**。总入口未承载任何阶段命令；三个 yml 未被合并。
- 修复动作：无。

### 探针 B（第 1 轮）— healthcheck 外置，compose 无内联 curl 长命令
- 现状路径：`.ci/scripts/backend-healthcheck.sh`、`.ci/scripts/frontend-healthcheck.sh` 仍在；
  `docker-compose.ci.yml` / `docker-compose.staging.yml` 的 healthcheck 均为
  `["CMD","sh","/opt/healthcheck.sh"]`（只读挂载脚本）。
- grep 结果：`rg curl docker-compose*.yml` 无命中。
- 有意例外：`db` 服务 healthcheck 使用 `mongosh --eval "db.adminCommand('ping')"`——这是
  数据库自带单行探针、非 curl 长命令，属可接受例外。
- 是否一致：**一致（通过）**。修复动作：无。

### 探针 C（第 1 轮）— Docker/CI 全部 `npm ci` + npmmirror，无 `npm install` 回归
- 现状路径：`backend/Dockerfile:6` `npm config set registry https://registry.npmmirror.com && npm ci --omit=dev`；
  `frontend/Dockerfile:4` `... && npm ci`。
- grep `npm install`：仅命中 `.ci/build.yml` 注释中「NEVER npm install」的说明性文字，
  以及本地开发文档，属约定允许（非构建脚本执行路径）。
- 是否一致：**一致（通过）**。修复动作：无。

### 探针 D（第 1 轮）— 端口 3731/8731/5731 与 `PET_*_PUBLISH_PORT` 对齐
- 现状路径：base `docker-compose.yml` 用字面量 8731/3731/5731（demo 默认）；
  `docker-compose.ci.yml`、`docker-compose.staging.yml` 用
  `${PET_API_PUBLISH_PORT:-8731}` / `${PET_WEB_PUBLISH_PORT:-3731}` / `${PET_DB_PUBLISH_PORT:-5731}`；
  `run-stage.sh` 默认值同样为 8731/3731/5731。
- 说明：demo 基础文件保留字面量是刻意的（一键演示无需 env），其默认值与参数化默认值一致。
- 是否一致：**一致（通过）**。修复动作：无。

### 探针 E（第 2 轮）— `PET_APP_ENV` 支持 demo/ci/staging，三份 compose 在矩阵表可查
- 现状路径：`run-stage.sh:47-55` 的 `case` 支持 demo/ci/staging 并对未知值报错退出 2；
  三份 compose 均存在；`docs/engineering/ci-docker-playbook.md §3.0` 有环境矩阵表。
- 是否一致：**一致（通过）**。修复动作：无。

### 探针 F（第 2 轮）— `PET_VITE_API_URL` 在 demo 与 staging 的差异在文档与 build args 链路同时存在
- 现状路径：
  - build args 链路：`docker-compose.staging.yml:65` `VITE_API_URL: "${PET_VITE_API_URL:-http://localhost:8731}"`；
    demo/ci 走 `/api`（Dockerfile `ARG VITE_API_URL=/api` 默认 + ci overlay 透传）。
  - `run-stage.sh:35-41` 按 env 设默认（staging→绝对源，其余→`/api`）。
  - 文档：playbook §3.0 矩阵表 + §4.1 传递链均说明差异与原因。
- 是否一致：**一致（通过）**。修复动作：无。

### 探针 G（第 2 轮）— `.ci/config/env.staging.example` 存在且键名大写蛇形
- 现状路径：`.ci/config/env.staging.example` 存在；键均为大写蛇形
  （`PET_APP_ENV`、`JWT_SECRET`、`MONGODB_URI`、`SEED_DEMO`、`UPLOAD_DIR` 等），示例值为假数据。
- 是否一致：**一致（通过）**。修复动作：无。

---

## 本轮发现并修复的冲突

### 冲突 #1 — release 镜像 tag 规则前后不一致，且缺少项目名前缀
- 发现：
  - 第 1 轮 `.ci/release.yml` 的 `tag_pattern` 为 `${PET_APP_ENV:-demo}-${PET_RELEASE_TAG:-local}`；
  - 第 1 轮 `run-stage.sh` 里打印的 tag 为 `${PET_APP_ENV}-${PET_RELEASE_TAG:-local}`
    （默认值 `demo` vs 空，两处不一致）；
  - 且均无 `PET_COMPOSE_PROJECT_NAME` 前缀，在多环境矩阵/多项目下 tag 会碰撞。
- 修复（改工程文件回到统一约定）：
  - 统一为 `${PET_COMPOSE_PROJECT_NAME}-${PET_APP_ENV}-${PET_RELEASE_TAG:-local}`；
  - `run-stage.sh` 新增 `release_tag()`，`stage_build` 按此 tag 给镜像打标；
  - `.ci/release.yml` 更新 `tagging` 并写明 OLD→NEW 迁移说明；
  - `.ci/scripts/release-manifest.sh` 与 `release-manifest.example.md` 均采用新规则。
- 结果：**已修复**。

### 冲突 #2 — 缺少可选 coverage 质量门禁
- 发现：第 2 轮 test 阶段只有 unit/smoke，无 coverage 存在性检查（第 3 轮要求可开启）。
- 修复：`run-stage.sh` unit 门禁新增 `PET_TEST_COVERAGE=1` 开关，跑
  `npm test -- --coverage` 并检查 `backend/coverage/` 下报告是否生成；默认关闭，
  不改业务测试、不设阈值。`.ci/test.yml` 补充 `coverage` 声明。
- 结果：**已修复**。

---

## 回溯校验清单

| 轮次 | 约定摘要 | 本轮核查结果 | 证据路径 |
| --- | --- | --- | --- |
| R1 | build/test/release/pipeline 职责分离，总入口只调度 | 通过 | `.ci/pipeline.yml`、`.ci/scripts/pipeline.sh`、`.ci/scripts/run-stage.sh` |
| R1 | healthcheck 外置，compose 无内联 curl | 通过 | `.ci/scripts/*-healthcheck.sh`、`docker-compose.ci.yml`、`docker-compose.staging.yml` |
| R1 | Docker/CI 全 `npm ci` + npmmirror，无 npm install 回归 | 通过 | `backend/Dockerfile:6`、`frontend/Dockerfile:4` |
| R1 | 端口 3731/8731/5731 与 `PET_*_PUBLISH_PORT` 对齐 | 通过 | `docker-compose*.yml`、`run-stage.sh:26-30` |
| R1 | release 镜像 tag 规则稳定统一 | 已修复 | `.ci/release.yml:36-39`、`run-stage.sh` `release_tag()` |
| R2 | `PET_APP_ENV` 支持 demo/ci/staging，矩阵表可查 | 通过 | `run-stage.sh:47-55`、`ci-docker-playbook.md §3.0` |
| R2 | `PET_VITE_API_URL` demo/staging 差异在文档与 build args 双在 | 通过 | `docker-compose.staging.yml:65`、`ci-docker-playbook.md §3.0/§4.1` |
| R2 | `.ci/config/env.staging.example` 存在且大写蛇形 | 通过 | `.ci/config/env.staging.example` |
| R3 | test 阶段可选 coverage 存在性门禁 | 已修复 | `run-stage.sh` unit 门禁、`.ci/test.yml:33-41` |
| R3 | release 三门禁（image_exists/health_gate/artifact_manifest） | 通过 | `.ci/release.yml`、`run-stage.sh` `release_gate_*`、`.ci/scripts/release-manifest.sh` |
