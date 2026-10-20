import hashlib
import os
import time

from flask import Flask, jsonify, request


app = Flask(__name__)


@app.get("/")
def index():
    print("Hello from the Datadog Cloud Run CD demo", flush=True)
    return jsonify(
        message="Datadog Cloud Run CD demo",
        service=os.getenv("DD_SERVICE", "datadog-cloud-run-cd-demo"),
        environment=os.getenv("DD_ENV", "staging"),
        version=os.getenv("DD_VERSION", "local"),
    )


@app.get("/health")
def health():
    return jsonify(status="ok")


@app.get("/work")
def work():
    iterations = min(max(request.args.get("iterations", default=2_000, type=int), 1), 20_000)
    started_at = time.perf_counter()
    digest = b"cloud-run"

    for _ in range(iterations):
        digest = hashlib.sha256(digest).digest()

    return jsonify(
        iterations=iterations,
        digest=digest.hex(),
        duration_ms=round((time.perf_counter() - started_at) * 1_000, 3),
    )


@app.get("/error")
def error():
    raise RuntimeError("Synthetic error for staging observability validation")


@app.errorhandler(RuntimeError)
def handle_runtime_error(error):
    app.logger.exception("Synthetic request failed")
    return jsonify(error=str(error)), 500
