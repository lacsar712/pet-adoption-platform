# Pet Adoption Platform — Release Manifest

> This is the committed TEMPLATE. The release stage renders a concrete copy to
> `.ci/out/release-manifest.md` by substituting the `{{PLACEHOLDER}}` tokens and
> appending the local `docker images` inventory. Do not edit the generated copy;
> change this template instead.

## Build identity

- Build environment (`PET_APP_ENV`): `{{PET_APP_ENV}}`
- Release/health target (`PET_RELEASE_ENV`): `{{PET_RELEASE_ENV}}`
- Compose project name (`PET_COMPOSE_PROJECT_NAME`): `{{PET_COMPOSE_PROJECT_NAME}}`
- Generated at (UTC): `{{GENERATED_AT}}`

## Images

Tag rule (unchanged since round 1):

- repository: `<PET_COMPOSE_PROJECT_NAME>-<service>`
- floating tag: `latest`
- release tag: `<PET_IMAGE_TAG>` (default `<PET_APP_ENV>-latest`)

| Service | Repository | Floating tag | Release tag |
| --- | --- | --- | --- |
| backend | `{{BACKEND_IMAGE}}` | `{{BACKEND_IMAGE}}:latest` | `{{BACKEND_IMAGE}}:{{PET_IMAGE_TAG}}` |
| frontend | `{{FRONTEND_IMAGE}}` | `{{FRONTEND_IMAGE}}:latest` | `{{FRONTEND_IMAGE}}:{{PET_IMAGE_TAG}}` |

## Key compose files

| File | Purpose |
| --- | --- |
| `docker-compose.yml` | demo default (db / backend / frontend, host ports 3731/8731/5731) |
| `docker-compose.ci.yml` | ci overlay (no published host ports, tighter healthchecks) |
| `docker-compose.staging.yml` | staging overlay (absolute `PET_VITE_API_URL`, quasi-production) |

## Key environment example

- `.ci/config/env.staging.example` — staging variable template (fake values,
  UPPER_SNAKE_CASE); copy to `.ci/config/env.staging` (git-ignored) for real use.

## Key healthcheck scripts (externalized, called by compose healthcheck)

- `.ci/scripts/backend-healthcheck.sh` — Node HTTP probe of `GET /health`
- `.ci/scripts/frontend-healthcheck.sh` — busybox wget probe of `GET /health`

## Base images & dependency discipline

- backend runtime: `docker.m.daocloud.io/library/node:20-slim`
- frontend builder: `docker.m.daocloud.io/library/node:20-alpine`
- frontend runtime: `docker.m.daocloud.io/library/nginx:alpine`
- database: `docker.m.daocloud.io/library/mongo:7`
- npm install in Docker/CI: `npm ci` only, registry `https://registry.npmmirror.com`
