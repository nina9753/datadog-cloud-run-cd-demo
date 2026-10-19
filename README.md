# Datadog Cloud Run CD demo

This public demo repository exercises a staging-only path from GitHub to Google Cloud Run and Datadog Serverless instrumentation.

The first `main` revision established an uninstrumented baseline. The current image adds the Python tracer and the in-container `serverless-init` process, while keeping the Datadog API key in Google Secret Manager.

## What this demo contains

- A small Python HTTP service with health and synthetic-work endpoints.
- The Datadog Python tracer and a digest-pinned `serverless-init` binary.
- A container build that records the Git repository and commit SHA in the image.
- A Cloud Build pipeline that builds, pushes, and deploys a Cloud Run revision.
- A Secret Manager reference for `DD_API_KEY`; the API-key value never enters GitHub or Cloud Build configuration.
- Cloud Run labels and environment variables that preserve source, service, environment, revision, and Cloud Build trigger identity.
- A minimal `service.datadog.yaml` entry for Software Catalog discovery.

No Datadog API key, application key, Google credential, project ID, or staging hostname is committed to this repository.

## Staging guardrails

Use a disposable GCP sandbox project and a Datadog staging organization. Do not install this demo into a production Datadog organization or reuse a production API key.

The checked-in pipeline deploys with:

- `DD_ENV=staging`
- zero minimum instances
- request-based CPU allocation (`--cpu-throttling`)
- a maximum of three instances

The API-key value remains external configuration in Secret Manager. The checked-in substitutions identify only the staging site and the secret resource name.

## Local run

```shell
docker build \
  --build-arg DD_GIT_REPOSITORY_URL=https://github.com/nina9753/datadog-cloud-run-cd-demo \
  --build-arg DD_GIT_COMMIT_SHA=local \
  --tag datadog-cloud-run-cd-demo:local .
docker run --rm --publish 8080:8080 datadog-cloud-run-cd-demo:local
./scripts/smoke-test.sh http://localhost:8080
```

## Connect the staging flow

Follow [the staging setup guide](docs/staging-setup.md). The intended relationship is:

```text
GitHub repository
  -> GCP Developer Connect / Cloud Build trigger
  -> Artifact Registry image
  -> Cloud Run revision
  -> Datadog staging deployment tracking, APM, logs, inventory, and Software Catalog
```

The Datadog GitHub integration and the GCP deployment connection are independent. The GitHub integration lets Datadog associate telemetry and catalog entities with this repository. Developer Connect and Cloud Build are what actually build and deploy source changes to Cloud Run.

## Validate instrumentation

After an instrumented revision deploys, verify that:

1. Deployment Tracking shows the commit and revision.
2. Requests to `/work` create traces in staging APM.
3. Logs correlate with `service`, `env`, and `version`.
4. Agent inventory reaches the staging EPRW pipeline.
5. The next integration crawl links the Cloud Run resource back to the Cloud Build trigger and GitHub repository.

The complete one-time connection procedure, trigger configuration, Secret Manager setup, verification checklist, and automation inputs are documented in [the staging setup guide](docs/staging-setup.md).
