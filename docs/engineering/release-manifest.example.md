# Release Manifest — Example / Reference

This is a **human reference** showing the shape of a rendered release manifest.
The actual machine-rendered file is `.ci/out/release-manifest.md`, produced by
`.ci/scripts/release.sh` from `.ci/release-manifest.template.md`, and is
git-ignored. The release stage does not push images or run git commands.

## Tag rule (stable across rounds)

```
<repository> = <PET_COMPOSE_PROJECT_NAME>-<service>
<tag>        = <PET_RELEASE_TAG>           (defaults to <PET_APP_ENV>)

Examples:
  pet-adoption-backend:staging
  pet-adoption-frontend:staging
  pet-adoption-backend:ci
  pet-adoption-frontend:demo
```

## Example rendered manifest

```markdown
# Pet Adoption Platform — Release Manifest

- Generated (UTC): 2026-08-03T12:00:00Z
- PET_APP_ENV: staging
- PET_COMPOSE_PROJECT_NAME: pet-adoption
- PET_RELEASE_TAG: staging
- PET_VITE_API_URL: http://localhost:8731
- Compose files: -f docker-compose.yml -f docker-compose.staging.yml

## Images

| Service  | Image                            | ID (short) | Size (bytes) |
|----------|----------------------------------|------------|--------------|
| backend  | pet-adoption-backend:staging     | abc123def456 | 123456789  |
| frontend | pet-adoption-frontend:staging    | 789ghi012jkl | 98765432   |

## Artifacts

| File                            | sha256                                 |
|---------------------------------|----------------------------------------|
| .ci/out/frontend-dist.tar.gz    | <64-char hex>                          |

## Key references

- Compose base: docker-compose.yml
- Compose overlays: docker-compose.ci.yml / docker-compose.staging.yml
- Env example: .ci/config/env.staging.example
- Healthchecks: .ci/scripts/backend-healthcheck.sh, .ci/scripts/frontend-healthcheck.sh
- Pipeline: .ci/pipeline.yml
```

## Required gates before this manifest is emitted

1. **image_exists**: both backend and frontend images exist locally under the env tag.
2. **health_gate**: the target env's containers pass the externalized healthcheck scripts.
3. **artifact_manifest**: merged compose config validates and `frontend-dist.tar.gz` exists.

If any gate fails, the release script exits non-zero and **no manifest is written**.
