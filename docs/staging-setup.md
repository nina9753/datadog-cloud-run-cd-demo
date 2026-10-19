# Staging setup

This guide keeps all Datadog data and credentials in staging while using a public GitHub repository and a disposable GCP sandbox project.

## 1. Prepare the GCP sandbox

Choose the project explicitly before running any command:

```shell
export DEMO_GCP_PROJECT='<sandbox-project-id>'
export DEMO_GCP_REGION='europe-west1'
gcloud config set project "$DEMO_GCP_PROJECT"
gcloud services enable \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  run.googleapis.com \
  secretmanager.googleapis.com
gcloud artifacts repositories create cloud-run-demo \
  --repository-format=docker \
  --location="$DEMO_GCP_REGION"
```

Grant the Cloud Build service account only the permissions required to push an image and deploy the demo. Keep the project isolated from production resources.

## 2. Connect GitHub to Cloud Build

In GCP, create a Developer Connect connection and authorize its GitHub app for only `nina9753/datadog-cloud-run-cd-demo`. Link the repository, then create a Cloud Build repository event trigger with:

- Event: push to `^main$`
- Configuration: `cloudbuild.yaml`
- Region: the same region as the Developer Connect connection
- Substitutions:
  - `_REGION=europe-west1`
  - `_AR_REPOSITORY=cloud-run-demo`
  - `_SERVICE_NAME=datadog-cloud-run-cd-demo`
  - `_GCB_TRIGGER_ID=<the trigger UUID>`

The explicit trigger UUID is added to the Cloud Run resource as `gcb-trigger-id`. That gives the GCP inventory crawler a deterministic path from the deployed service to the Cloud Build trigger and then to the Developer Connect repository link and clone URL.

## 3. Connect the repository to Datadog staging

Open the GitHub integration in the Datadog staging organization. Install or configure the staging GitHub app for the `nina9753` account and grant it access only to this repository. Confirm that staging can resolve the repository URL and commit metadata.

This integration does not deploy the service. It provides source-code and pull-request context that Datadog can associate with telemetry and catalog entities.

## 4. Connect the GCP sandbox to Datadog staging

Create a dedicated service account for the Datadog staging GCP integration and connect only the sandbox project. Enable resource collection for Cloud Run, Cloud Build, and Developer Connect. The staging integration crawler should collect:

- the Cloud Run service and revision,
- the `gcb-trigger-id` label,
- the Cloud Build trigger,
- the Developer Connect repository link, and
- its GitHub clone URL.

Crawler discovery is asynchronous. Treat the crawler interval as separate from deployment completion; do not use a fixed 15-minute promise as a correctness condition.

## 5. Deploy the baseline

Run the trigger once or merge a small change to `main`. Then verify:

```shell
gcloud run services describe datadog-cloud-run-cd-demo \
  --project="$DEMO_GCP_PROJECT" \
  --region="$DEMO_GCP_REGION" \
  --format='yaml(metadata.labels,spec.template.metadata,spec.template.spec.containers)'
```

Pass the service URL to the smoke test:

```shell
./scripts/smoke-test.sh 'https://SERVICE_URL'
```

At this point the application is deliberately not instrumented, so the absence of Datadog traces and agent inventory is expected.

## 6. Add staging Datadog instrumentation in a pull request

The follow-up pull request should:

1. Add `ddtrace` to the Python application.
2. Add the Datadog `serverless-init` sidecar or use `datadog-ci cloud-run instrument` with a digest-pinned image.
3. Read a staging-only `DD_API_KEY` from GCP Secret Manager.
4. Set the exact staging `DD_SITE` supplied by the staging organization; do not default to a production site.
5. Preserve `DD_SERVICE`, `DD_ENV=staging`, `DD_VERSION`, `DD_GIT_REPOSITORY_URL`, and `DD_GIT_COMMIT_SHA`.
6. Mark the deployment against the same staging site after Cloud Run deployment succeeds.

The application image build remains the customer's normal CD responsibility. Datadog's recommendation changes source or deployment configuration; Cloud Build performs the build and creates the revision.

## 7. Validate the end-to-end result

After merge and deployment:

- call `/`, `/work`, and `/error` to generate requests, CPU work, and an error trace;
- confirm the commit in Deployment Tracking;
- confirm traces and correlated logs in staging APM;
- confirm serverless agent inventory in the staging EPRW-backed table;
- confirm Software Catalog associates the service with this repository; and
- after a crawler cycle, confirm the Cloud Run resource resolves through the trigger to the GitHub clone URL.

Because the baseline uses `min=0` and request-based CPU allocation, it should not be used to assert that a background inventory reporter runs while the service is scaled to zero. Exercise that behavior separately by changing to instance-based billing and a non-zero minimum instance count.
