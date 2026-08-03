# Pet Adoption Platform — Release Manifest

<!--
  Tracked TEMPLATE rendered by .ci/scripts/release.sh into
  .ci/out/release-manifest.md. Tokens use @@NAME@@ and are substituted with
  sed at render time. Do not put real secrets here.
  The rendered .ci/out/ copy is git-ignored.
-->

- Generated (UTC): @@BUILD_TIME@@
- PET_APP_ENV: @@PET_APP_ENV@@
- PET_COMPOSE_PROJECT_NAME: @@PET_COMPOSE_PROJECT_NAME@@
- PET_RELEASE_TAG: @@PET_RELEASE_TAG@@
- PET_VITE_API_URL: @@PET_VITE_API_URL@@
- Compose files: @@COMPOSE_FILES@@

## Images (tag rule: <project>-<service>:<tag>)

| Service | Image | ID (short) | Size (bytes) |
|---------|-------|------------|--------------|
| backend | @@BACKEND_IMAGE@@ | @@BACKEND_ID@@ | @@BACKEND_SIZE@@ |
| frontend | @@FRONTEND_IMAGE@@ | @@FRONTEND_ID@@ | @@FRONTEND_SIZE@@ |

## Artifacts

| File | sha256 |
|------|--------|
| @@DIST_ARCHIVE@@ | @@DIST_SHA@@ |

## Key references

- Compose base: docker-compose.yml
- Compose overlays: docker-compose.ci.yml / docker-compose.staging.yml
- Env example: .ci/config/env.staging.example
- Healthchecks:
  - .ci/scripts/backend-healthcheck.sh
  - .ci/scripts/frontend-healthcheck.sh
- Pipeline: .ci/pipeline.yml (.ci/scripts/run-pipeline.sh)

## Notes

- This manifest is produced locally/CI-side; images have NOT been pushed.
- No git operation is performed by the release stage.
- Unit tests rely on mongodb-memory-server and do not require a live Mongo.
