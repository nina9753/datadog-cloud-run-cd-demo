#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <service-url>" >&2
  exit 2
fi

service_url="${1%/}"
curl_args=(--fail --silent --show-error)

if [[ -n "${CLOUD_RUN_IDENTITY_TOKEN:-}" ]]; then
  curl_args+=(--header "Authorization: Bearer ${CLOUD_RUN_IDENTITY_TOKEN}")
fi

curl "${curl_args[@]}" "$service_url/health"
curl "${curl_args[@]}" "$service_url/"
curl "${curl_args[@]}" "$service_url/work?iterations=5000"

status_code="$(curl "${curl_args[@]}" --output /dev/null --write-out '%{http_code}' "$service_url/error" || true)"
if [[ "$status_code" != "500" ]]; then
  echo "expected /error to return 500, got $status_code" >&2
  exit 1
fi

echo "smoke test passed"
