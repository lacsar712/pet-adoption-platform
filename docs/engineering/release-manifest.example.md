# Release Manifest (example / template)

> This is a **template** showing what `.ci/scripts/release-manifest.sh` emits at
> `.ci/out/release-manifest.md`. It is generated locally only — no image push,
> no git. Values below use the defaults `PET_COMPOSE_PROJECT_NAME=pet-adoption`,
> `PET_APP_ENV=staging`, `PET_RELEASE_TAG=local`.

- Generated for: PET_APP_ENV=`staging`
- Project name : `pet-adoption`
- Release tag  : `local`

## Images

| service | image | release tag rule |
| --- | --- | --- |
| backend  | `pet-adoption-backend`  | `pet-adoption-staging-local` |
| frontend | `pet-adoption-frontend` | `pet-adoption-staging-local` |

Tag rule: `${PET_COMPOSE_PROJECT_NAME}-${PET_APP_ENV}-${PET_RELEASE_TAG}`

> MIGRATION NOTE (round 3): round 1 used `${PET_APP_ENV}-${PET_RELEASE_TAG}`
> (no project prefix). Round 3 prefixes the project name to avoid cross-project
> / multi-env tag collisions. See `docs/engineering/consistency-audit.md`.

## Key compose files

- `docker-compose.yml` (demo base)
- `docker-compose.ci.yml` (ci overlay)
- `docker-compose.staging.yml` (staging overlay)

## Key env example

- `.ci/config/env.staging.example`

## Key healthcheck scripts

- `.ci/scripts/backend-healthcheck.sh`
- `.ci/scripts/frontend-healthcheck.sh`

## How to regenerate

```bash
PET_APP_ENV=staging PET_RELEASE_TAG=local sh .ci/scripts/release-manifest.sh
# output -> .ci/out/release-manifest.md
```
