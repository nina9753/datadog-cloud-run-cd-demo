#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <service-url>" >&2
  exit 2
fi

service_url="${1%/}"

curl --fail --silent --show-error "$service_url/health"
curl --fail --silent --show-error "$service_url/"
curl --fail --silent --show-error "$service_url/work?iterations=5000"

status_code="$(curl --silent --output /dev/null --write-out '%{http_code}' "$service_url/error")"
if [[ "$status_code" != "500" ]]; then
  echo "expected /error to return 500, got $status_code" >&2
  exit 1
fi

echo "smoke test passed"
