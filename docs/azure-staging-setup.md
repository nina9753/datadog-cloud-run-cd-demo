# Azure Container Apps staging CD

This adds a second deployment target to the existing GitHub repository. The
Cloud Run Dockerfile, application, and Cloud Build configuration remain unchanged.
The Azure workflow is not ready to enable until the prerequisites below exist.

## One-time prerequisites

Reuse the verified Fleet example infrastructure:

| Setting | Value |
| --- | --- |
| Subscription | `serverless-dev` (`1dd25961-a5c7-45bf-a5ba-c1475d365cc7`) |
| Resource group | `dd-serverless-test-aca` |
| Container Apps environment | `dd-serverless-env-eastus2` |
| Container registry | `ddsvlstestaca` (`ddsvlstestaca.azurecr.io`) |
| New app name | `datadog-aca-cd-demo` |
| Application container name | `app` |
| Datadog site | `datad0g.com` (staging) |

The app and its deployment identity must be new; do not change the existing
`svrc1016az-*` Fleet examples. The registry uses classic RBAC. Existing examples
use registry credentials, but this app should use managed identity instead.

1. Verify access to the environment and registry above.
2. Create a dedicated Container App with one application container, external HTTPS
   ingress on port 8080, single-revision mode, and a small consumption allocation
   (start with 0.5 CPU, 1 GiB memory, zero minimum and one maximum replica).
   The smoke test requires an endpoint reachable by the GitHub-hosted runner.
3. Give the app a managed identity with image-pull permission on the selected
   registry and configure the app to use that identity for registry access.
4. Configure `DD_API_KEY` using an Azure Container Apps secret reference, and set
   `DD_SITE` to the intended Datadog staging site. Never put the API key in the
   Dockerfile, build arguments, workflow YAML, or source control. Decide whether
   agent log collection or existing Azure forwarding owns logs to avoid duplicates.
5. Create a dedicated GitHub OIDC deployment identity. Restrict its federation
   subject to `repo:nina9753/datadog-cloud-run-cd-demo:environment:azure-staging`,
   issuer `https://token.actions.githubusercontent.com`, and audience
   `api://AzureADTokenExchange`. Scope its permissions to updating this app and
   pushing images to this registry; do not grant subscription-wide Contributor.
   Registry permissions must match whether the registry uses classic RBAC or ABAC.
6. Create a GitHub environment named `azure-staging`, restrict deployments to
   `main`, and configure these environment variables:

   - `AZURE_CLIENT_ID`
   - `AZURE_TENANT_ID`
   - `AZURE_SUBSCRIPTION_ID`
   - `AZURE_RESOURCE_GROUP`
   - `AZURE_CONTAINER_APP`
   - `AZURE_CONTAINER_NAME`
   - `AZURE_ACR_NAME`

## Deployment and validation

After review and merge, pushes to `main` affecting the application, Dockerfile,
Docker ignore rules, or Azure workflow build and deploy a SHA-tagged image.
Manual runs are also supported, but only from `main`. Updates preserve existing
app secrets and unrelated environment variables. Single-revision mode is required
so the smoke test checks the revision that should receive traffic.

Azure uses `DD_SERVICE=datadog-azure-container-app-cd-demo`, `DD_ENV=staging`, and
the deployed commit as `DD_VERSION`. Both platforms share `DD_GIT_REPOSITORY_URL`
and report their actual deployed commit, retaining the existing Datadog Source
Code Integration connection.

The workflow verifies the endpoint's service and commit. Separately verify
serverless-init inventory, traces, logs, and source links in Datadog; a successful
HTTP smoke test does not prove telemetry delivery.

Shared application changes can deploy to both clouds. Azure's path filter prevents
GCP-only configuration changes from deploying to Azure, but it does not change the
existing Cloud Build trigger: Azure-only commits may still trigger a GCP build
unless that trigger's file filters are separately configured.

No Azure resources or GitHub environment are created by this workflow. Review the
resource choices and bootstrap permissions before enabling it.
