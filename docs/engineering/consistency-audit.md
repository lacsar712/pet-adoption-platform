# 跨轮一致性审计 (Consistency Audit)

> 第 3 轮强制审计：逐条对照第 1、2 轮确立的工程约定，检查现状是否自相矛盾；
> 若发现冲突，优先改工程文件回到约定，而不是改文档迁就错误实现。
> 本轮审计不涉及任何业务代码（宠物 CRUD / 鉴权 / 上传均未改动）。

---

## 探针 A：阶段职责是否仍分离，命令有没有回迁到总入口？

- **约定来源**：第 1 轮 — `.ci/build.yml` / `.ci/test.yml` / `.ci/release.yml` / `.ci/pipeline.yml` 职责分离；总入口只调度。
- **现状**：
  - [.ci/pipeline.yml](../../.ci/pipeline.yml) 只声明阶段顺序、环境矩阵与健康检查位置，不含具体命令。
  - [.ci/scripts/run-pipeline.sh](../../.ci/scripts/run-pipeline.sh) 只用 `--stages` / `--test-gate` 选择并 `bash <stage>.sh`，没有复制 build/test/release 的具体命令。
  - build / test / release 的可执行逻辑分别在 [build.sh](../../.ci/scripts/build.sh)、[test.sh](../../.ci/scripts/test.sh)、[release.sh](../../.ci/scripts/release.sh)。
  - 第 3 轮新增的 release 门禁逻辑全部落在 `.ci/release.yml`（声明）与 `release.sh`（执行）内，没有塞进 pipeline。
- **结论**：✅ 一致。

## 探针 B：healthcheck 是否仍由 `.ci/scripts/` 外置脚本承担？compose 里有没有内联 curl？

- **约定来源**：第 1 轮 — healthcheck 外置，compose 的 `healthcheck.test` 调用脚本，禁止内联长 curl/wget。
- **现状**：
  - [backend-healthcheck.sh](../../.ci/scripts/backend-healthcheck.sh)、[frontend-healthcheck.sh](../../.ci/scripts/frontend-healthcheck.sh) 仍在 `.ci/scripts/`，均 `set -eu` 且支持重试参数。
  - [docker-compose.yml](../../docker-compose.yml) 的 `healthcheck.test` 为 `["CMD","sh","/tmp/<svc>-healthcheck.sh"]`，脚本通过只读卷挂载进容器。
  - 全仓 `docker-compose*.yml` 中无 curl/wget 内联（grep 仅命中 staging 文件中“no inline curl”的注释文字）。
  - 第 3 轮 release 的 `health_gate` 复用 `run_service_healthcheck`，最终仍是 `docker compose exec ... sh /tmp/<svc>-healthcheck.sh`，没有新写内联探测命令。
- **结论**：✅ 一致。

## 探针 C：Docker/CI 是否仍全部 `npm ci` + npmmirror？有没有回归成 `npm install`？

- **约定来源**：第 1 轮 — Dockerfile 与 CI 全程 `npm ci`，registry 为 `https://registry.npmmirror.com`。
- **现状**：
  - [backend/Dockerfile](../../backend/Dockerfile)：`ARG NPM_REGISTRY=...npmmirror...` + `npm ci --omit=dev`。
  - [frontend/Dockerfile](../../frontend/Dockerfile)：`ARG NPM_REGISTRY=...` + `npm ci`。
  - [test.sh](../../.ci/scripts/test.sh) 的 unit 门禁在容器内执行 `npm ci`；[build.sh](../../.ci/scripts/build.sh) 通过 compose build 透传 `NPM_REGISTRY`。
  - 对 `Dockerfile` / `*.yml` / `*.sh` 全仓 grep `npm install`：**0 命中**。
- **结论**：✅ 一致。

## 探针 D：端口约定 3731/8731/5731 与 `PET_*_PUBLISH_PORT` 是否仍对齐？

- **约定来源**：第 1 轮 — 前端 3731、后端 8731、DB 5731；变量 `PET_WEB/API/DB_PUBLISH_PORT`。
- **现状**：
  - [docker-compose.yml](../../docker-compose.yml)：`${PET_WEB_PUBLISH_PORT:-3731}:80`、`${PET_API_PUBLISH_PORT:-8731}:8731`、`${PET_DB_PUBLISH_PORT:-5731}:27017`。
  - [docker-compose.ci.yml](../../docker-compose.ci.yml) 用 `ports: !override []` 清空宿主端口；staging 不覆盖端口，沿用 demo 的发布端口。
  - 三份 YAML 规格（build/pipeline）的 env 默认值仍是 3731/8731/5731。
  - 容器内监听端口未变：后端 8731、前端 80、DB 27017。
- **结论**：✅ 一致。

## 探针 E：`PET_APP_ENV` 是否支持 demo/ci/staging？三份 compose 是否在矩阵表可查？

- **约定来源**：第 2 轮 — 三环境矩阵。
- **现状**：
  - [lib_compose.sh](../../.ci/scripts/lib_compose.sh) 的 `compose_files_for_env` 支持 `demo|ci|staging`，其它值报错。
  - 三份覆盖文件齐备：[docker-compose.yml](../../docker-compose.yml)、[docker-compose.ci.yml](../../docker-compose.ci.yml)、[docker-compose.staging.yml](../../docker-compose.staging.yml)。
  - 矩阵表见 [ci-docker-playbook.md](ci-docker-playbook.md) 第 2 节，且 [pipeline.yml](../../.ci/pipeline.yml) 的 `matrix:` 段同步声明。
- **结论**：✅ 一致。

## 探针 F：`PET_VITE_API_URL` 在 demo(`/api`) 与 staging(`http://localhost:8731`) 的差异是否在文档与 build-args 链路上同时存在？

- **约定来源**：第 2 轮 — demo/ci 用 `/api`（Nginx 反代），staging 用绝对 URL。
- **现状**：
  - 文档：playbook 第 2、6 节明确差异与原因（构建期注入、staging 可能跨源）。
  - 脚本：[lib_compose.sh](../../.ci/scripts/lib_compose.sh) 的 `default_vite_api_url` 对 staging 返回 `http://localhost:8731`，其余返回 `/api`。
  - compose build args：根 compose 默认 `VITE_API_URL: ${PET_VITE_API_URL:-/api}`；[docker-compose.staging.yml](../../docker-compose.staging.yml) 的 frontend 覆盖为 `${PET_VITE_API_URL:-http://localhost:8731}`；backend 不再接收该参数（第 2 轮已修复误传）。
  - Dockerfile：[frontend/Dockerfile](../../frontend/Dockerfile) `ARG VITE_API_URL=/api` → `ENV` → `npm run build`。
- **结论**：✅ 一致。

## 探针 G：`.ci/config/env.staging.example` 是否存在且键名全大写蛇形？

- **约定来源**：第 2 轮。
- **现状**：文件存在于 [env.staging.example](../../.ci/config/env.staging.example)，键名全部 `UPPER_SNAKE_CASE`（`PET_APP_ENV`、`JWT_SECRET`、`MONGODB_URI`、`SEED_DEMO`、`UPLOAD_DIR` 等），值为假数据；私有 `env.staging` 已被 `.gitignore` 忽略，仅 `*.example` 可入库。
- **结论**：✅ 一致。

---

## 本轮审计发现并已修复的冲突

1. **镜像 tag 默认值自相矛盾（第 2 轮遗留）**
   - 问题：[docker-compose.yml](../../docker-compose.yml) 与脚本已把镜像 tag 默认改为「按环境」（`${PET_RELEASE_TAG:-${PET_APP_ENV:-demo}}`，如 `pet-adoption-backend:staging`），但 [build.yml](../../.ci/build.yml) 与 [pipeline.yml](../../.ci/pipeline.yml) 的 `env.PET_RELEASE_TAG` 仍写死 `"latest"`，release.yml 的 `image_exists` 也按 `latest` 校验——导致 build 产出的 tag 与 release 校验的 tag 对不上。
   - 修复：把 build.yml / pipeline.yml 的 `PET_RELEASE_TAG` 默认改为空（由 `default_release_tag()` 解析为 `PET_APP_ENV`），并在 release.yml 中显式声明 tag 规则 `${PET_COMPOSE_PROJECT_NAME}-<service>:${PET_RELEASE_TAG:-$PET_APP_ENV}`。未引入新 tag 语法，只是把第 2 轮已确立的按环境 tag 贯穿到规格文件。
2. **release 引用了不存在的清单模板（第 3 轮草稿遗留）**
   - 问题：[release.sh](../../.ci/scripts/release.sh) 读取 `.ci/release-manifest.template.md` 但该文件缺失，门禁无法渲染清单。
   - 修复：新增 [.ci/release-manifest.template.md](../../.ci/release-manifest.template.md)（`@@PLACEHOLDER@@` 占位模板）与人工参考 [release-manifest.example.md](release-manifest.example.md)；release.sh 全部门禁通过后才从模板渲染 `.ci/out/release-manifest.md`。

---

## 回溯校验清单

| 轮次 | 约定摘要 | 本轮核查结果 | 证据路径 |
|------|----------|--------------|----------|
| 第 1 轮 | 四文件职责分离、总入口只调度 | 通过 | [pipeline.yml](../../.ci/pipeline.yml)、[run-pipeline.sh](../../.ci/scripts/run-pipeline.sh) |
| 第 1 轮 | healthcheck 外置、禁止内联 curl | 通过 | [backend-healthcheck.sh](../../.ci/scripts/backend-healthcheck.sh)、[frontend-healthcheck.sh](../../.ci/scripts/frontend-healthcheck.sh)、[docker-compose.yml](../../docker-compose.yml) |
| 第 1 轮 | Docker/CI 全程 `npm ci` + npmmirror | 通过 | [backend/Dockerfile](../../backend/Dockerfile)、[frontend/Dockerfile](../../frontend/Dockerfile)、[test.sh](../../.ci/scripts/test.sh) |
| 第 1 轮 | 端口 3731/8731/5731 与 `PET_*_PUBLISH_PORT` | 通过 | [docker-compose.yml](../../docker-compose.yml)、[docker-compose.ci.yml](../../docker-compose.ci.yml) |
| 第 2 轮 | `PET_APP_ENV` 支持 demo/ci/staging 三值 | 通过 | [lib_compose.sh](../../.ci/scripts/lib_compose.sh)、[docker-compose.staging.yml](../../docker-compose.staging.yml)、[ci-docker-playbook.md](ci-docker-playbook.md) |
| 第 2 轮 | demo `/api` vs staging 绝对 URL 差异贯通 | 通过 | [lib_compose.sh](../../.ci/scripts/lib_compose.sh)、[docker-compose.staging.yml](../../docker-compose.staging.yml)、[frontend/Dockerfile](../../frontend/Dockerfile) |
| 第 2 轮 | `.ci/config/env.staging.example` 大写蛇形假数据 | 通过 | [env.staging.example](../../.ci/config/env.staging.example) |
| 第 3 轮 | release 三门禁：image_exists / health_gate / artifact_manifest | 通过（本轮新增） | [release.yml](../../.ci/release.yml)、[release.sh](../../.ci/scripts/release.sh)、[release-manifest.template.md](../../.ci/release-manifest.template.md) |
| 第 3 轮 | test 阶段可选 coverage 存在性门禁（默认关） | 通过（本轮新增） | [test.yml](../../.ci/test.yml)、[test.sh](../../.ci/scripts/test.sh)（`TEST_COVERAGE`） |
| 第 3 轮 | 修复 tag 默认值不一致（latest vs 按环境） | 已修复 | [build.yml](../../.ci/build.yml)、[pipeline.yml](../../.ci/pipeline.yml)、[release.yml](../../.ci/release.yml) |
| 第 3 轮 | 补齐 release 清单模板缺失 | 已修复 | [release-manifest.template.md](../../.ci/release-manifest.template.md)、[release-manifest.example.md](release-manifest.example.md) |
| 跨轮 | 禁止 git 操作、禁止真实推送、禁止业务改动 | 通过 | release.sh 仅本地 `docker image inspect` + 渲染文件；无 git/push 调用 |
