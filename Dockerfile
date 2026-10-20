FROM gcr.io/datadoghq/serverless-init@sha256:d741777c3f11ef4c0e59eb4200316789183bf2eb24b970684104f0a17cb30d5a AS datadog-init

FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

ARG DD_GIT_REPOSITORY_URL
ARG DD_GIT_COMMIT_SHA
ENV DD_GIT_REPOSITORY_URL=${DD_GIT_REPOSITORY_URL} \
    DD_GIT_COMMIT_SHA=${DD_GIT_COMMIT_SHA}

WORKDIR /app

RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY app/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir --requirement requirements.txt

COPY app/ ./
COPY --from=datadog-init /datadog-init /app/datadog-init

RUN useradd --create-home --uid 10001 appuser
USER appuser

ENTRYPOINT ["/app/datadog-init"]
CMD ["ddtrace-run", "gunicorn", "--bind", "0.0.0.0:8080", "--workers", "1", "--threads", "8", "--timeout", "0", "main:app"]
