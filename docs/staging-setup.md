# Staging end-to-end setup

This runbook records the complete staging-only connection between Datadog, GitHub, Google Developer Connect, Cloud Build, Artifact Registry, Secret Manager, and Cloud Run. It is also the source of truth for a future onboarding skill or automation.

## Architecture and ownership boundaries

```text
GitHub push to main
  -> Developer Connect repository link
  -> regional Cloud Build trigger
  -> cloudbuild.yaml
  -> Artifact Registry image
  -> Cloud Run revision
  -> ddtrace + serverless-init
  -> Datadog staging

Datadog GitHub integration ---------------------> source and repository context
Datadog GCP integration ------------------------> Cloud Run/Build resource metadata and metrics
Google Secret Manager -> DD_API_KEY reference --> runtime telemetry authentication
```

The integrations are complementary:

- Developer Connect and Cloud Build perform continuous deployment.
- The Datadog GitHub integration supplies repository, commit, pull-request, and source context; it does not deploy code.
- The Datadog GCP integration collects cloud resource metadata and provider metrics; it does not create application traces.
- `ddtrace` creates application spans. In-container `serverless-init` receives and forwards traces, enhanced metrics, and configured logs.

## Current demo resources

| Resource | Value |
|---|---|
| GCP project | `datadog-serverless-gcp-demo` |
| Region | `europe-west1` |
| GitHub repository | `nina9753/datadog-cloud-run-cd-demo` |
| Developer Connect connection | `github-nina9753-cloud-run-cd-demo` |
| Cloud Build trigger ID | `7ee45bdd-e8e3-45d5-9bf7-9ac0fcc4bca9` |
| Cloud Run service | `datadog-cloud-run-cd-demo-git` |
| Artifact Registry repository | `cloud-run-source-deploy` |
| Artifact Registry image path | `nina9753-datadog-cloud-run-cd-demo/datadog-cloud-run-cd-demo-git` |
| Runtime service account | `546765393806-compute@developer.gserviceaccount.com` |
| API-key secret | `dd-api-key-gcp-staging` |
| Datadog site | `datad0g.com` |
| Datadog service | `datadog-cloud-run-cd-demo` |
| Datadog environment | `staging` |

## 1. Connect GitHub to Datadog staging

1. Open the GitHub Apps integration in the Datadog staging organization.
2. Connect the `nina9753` personal GitHub account.
3. Limit the Datadog GitHub App installation to `nina9753/datadog-cloud-run-cd-demo`.
4. In the integration's **Repositories** tab, confirm that `datadog-cloud-run-cd-demo` is listed.

This grants Datadog repository context only. It does not grant GCP deployment access and does not expose other repositories when the installation is limited to the selected repository.

## 2. Connect the GCP project to Datadog staging

The Datadog GCP integration uses a dedicated integration service account. This is distinct from the Cloud Run runtime and Cloud Build service accounts.

1. Open **Integrations → Google Cloud Platform** in Datadog staging.
2. Select the service account associated with the Serverless GCP Demo project.
3. Confirm that `datadog-serverless-gcp-demo` is in its project scope.
4. Enable the resource collection needed for Cloud Run and Cloud Build.
5. Keep provider log collection and runtime log collection separate to avoid duplicate logs.

Crawler discovery is asynchronous. Deployment success does not imply that the resource relationship is immediately visible in Datadog.

## 3. Connect GitHub to GCP Developer Connect

In the GCP project:

1. Start a Developer Connect GitHub connection in `europe-west1`.
2. Name it `github-nina9753-cloud-run-cd-demo`.
3. Leave data residency disabled unless the demo explicitly requires it.
4. Leave KMS blank unless customer-managed encryption is required.
5. Enable the Developer Connect proxy.
6. Authorize the GitHub App for only `nina9753/datadog-cloud-run-cd-demo`.
7. Create a repository link for that repository.

The Cloud Build execution identity needs permission to fetch the repository token:

```shell
gcloud projects add-iam-policy-binding datadog-serverless-gcp-demo \
  --member='serviceAccount:546765393806-compute@developer.gserviceaccount.com' \
  --role='roles/developerconnect.readTokenAccessor'
```

Allow IAM changes to propagate before the first build. The original build was started only seconds after this grant and failed to fetch the token; retrying after propagation succeeded.

## 4. Configure one regional Cloud Build trigger

Only one active push trigger should deploy this service. The existing trigger already listens for pushes to `main`; edit it to use the repository configuration file instead of creating a second active trigger.

1. Open **Cloud Build → Triggers** in `europe-west1`.
2. Edit trigger `cloudrun-datadog-cloud-run-cd-demo-git-europe-west1-nina9753vmy`.
3. Keep the Developer Connect repository link.
4. Event: **Push to a branch**.
5. Branch regex: `^main$`.
6. Configuration: **Cloud Build configuration file**.
7. File location: `/cloudbuild.yaml`.
8. Keep the current build service account.
9. Save the trigger.

If the console cannot convert the generated inline trigger, create one replacement trigger with these settings and disable the old trigger before enabling the replacement. Never leave both active, or every push will deploy twice.

The checked-in substitutions target the existing service, repository, secret, and trigger label. Every push builds two tags (`$COMMIT_SHA` and `latest`), pushes them, then deploys the immutable commit tag.

## 5. Store and authorize the staging API key

The secret already exists. Do not print, download, copy into GitHub, or pass its value as a Cloud Build substitution.

Grant the Cloud Run runtime service account access to this one secret:

```shell
gcloud secrets add-iam-policy-binding dd-api-key-gcp-staging \
  --project=datadog-serverless-gcp-demo \
  --member='serviceAccount:546765393806-compute@developer.gserviceaccount.com' \
  --role='roles/secretmanager.secretAccessor'
```

`cloudbuild.yaml` deploys the reference as:

```text
DD_API_KEY=dd-api-key-gcp-staging:latest
```

Cloud Run resolves the value when the revision starts. The service configuration, build logs, and Git repository contain only the secret name.

## 6. Runtime instrumentation and environment

The Docker image includes:

- `ddtrace`, pinned in `app/requirements.txt`;
- a digest-pinned `serverless-init` binary copied from the Datadog image;
- `serverless-init` as the container entrypoint; and
- Gunicorn started through `ddtrace-run`.

The deployment configures:

| Variable | Source |
|---|---|
| `DD_API_KEY` | Secret Manager reference |
| `DD_SITE=datad0g.com` | Cloud Build deployment configuration |
| `DD_SERVICE=datadog-cloud-run-cd-demo` | Cloud Build deployment configuration |
| `DD_ENV=staging` | Cloud Build deployment configuration |
| `DD_VERSION=$COMMIT_SHA` | Cloud Build built-in substitution |
| `DD_GIT_REPOSITORY_URL` | Cloud Build deployment configuration and image metadata |
| `DD_GIT_COMMIT_SHA=$COMMIT_SHA` | Cloud Build built-in substitution and image metadata |
| `DD_LOGS_ENABLED=true` | Cloud Build deployment configuration |
| `DD_LOGS_INJECTION=true` | Cloud Build deployment configuration |
| `DD_SOURCE=python` | Cloud Build deployment configuration |

Do not set `DD_AGENT_HOST` or `DD_TRACE_AGENT_URL` for this in-container serverless configuration.

## 7. Deploy and verify

After the secret IAM binding and trigger edit are complete, merge or push a commit to `main`. No schedule is required: the GitHub push event starts the build immediately.

Verify the build:

```shell
gcloud builds list \
  --project=datadog-serverless-gcp-demo \
  --region=europe-west1 \
  --filter='buildTriggerId=7ee45bdd-e8e3-45d5-9bf7-9ac0fcc4bca9' \
  --sort-by='~createTime' \
  --limit=5
```

Verify the deployed image, secret reference, and environment without reading the secret value:

```shell
gcloud run services describe datadog-cloud-run-cd-demo-git \
  --project=datadog-serverless-gcp-demo \
  --region=europe-west1 \
  --format='yaml(status.url,status.latestReadyRevisionName,spec.template.spec.containers)'
```

The service currently requires authentication. Generate traffic with an identity token:

```shell
service_url="$(gcloud run services describe datadog-cloud-run-cd-demo-git \
  --project=datadog-serverless-gcp-demo \
  --region=europe-west1 \
  --format='value(status.url)')"
identity_token="$(gcloud auth print-identity-token)"

curl --fail --header "Authorization: Bearer $identity_token" "$service_url/"
curl --fail --header "Authorization: Bearer $identity_token" "$service_url/work?iterations=5000"
curl --header "Authorization: Bearer $identity_token" "$service_url/error"

CLOUD_RUN_IDENTITY_TOKEN="$identity_token" ./scripts/smoke-test.sh "$service_url"
```

Then verify in Datadog staging:

1. APM has traces for `service:datadog-cloud-run-cd-demo env:staging`.
2. Logs have `service`, `env`, `version`, `trace_id`, and `span_id` correlation where supported.
3. Deployment Tracking resolves the commit and repository.
4. Serverless inventory reports the running `serverless-init` build.
5. Software Catalog associates the service with this repository.
6. After a crawler cycle, the Cloud Run resource links through the `gcb-trigger-id` label to the Cloud Build trigger and Developer Connect repository.

## 8. Automation contract

A future skill or automation should accept these inputs rather than hard-coding them:

- GCP project and region;
- GitHub owner, repository, and branch regex;
- Developer Connect connection and repository-link names;
- Artifact Registry repository and image path;
- Cloud Run service and runtime service account;
- Datadog site, service, and environment;
- Secret Manager secret name; and
- whether the Cloud Run endpoint is authenticated.

The automation should be idempotent and apply these phases independently:

1. Validate GitHub App scope and Datadog GitHub repository visibility.
2. Validate the Datadog GCP integration project scope.
3. Create or reuse Developer Connect resources.
4. Grant only required IAM roles.
5. Create or update exactly one regional push trigger.
6. Create or update the Secret Manager reference without reading the secret value.
7. Build and deploy an immutable commit-tagged image.
8. Generate test traffic and verify telemetry.
9. Report drift without deleting or replacing unrelated resources.

Never automate API-key retrieval into logs, prompts, shell history, Git commits, Cloud Build substitutions, or plain Cloud Run environment values.
