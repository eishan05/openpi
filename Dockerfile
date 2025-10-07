# Dockerfile for serving a PI policy.
# Based on UV's instructions: https://docs.astral.sh/uv/guides/integration/docker/#developing-in-a-container

# Build the container:
# docker build -t eishan05/open-pi-server:latest .

# Run the container (no bind mount required):
# docker run --rm -it --network=host --gpus=all eishan05/open-pi-server:latest /bin/bash

FROM nvidia/cuda:12.2.2-cudnn8-runtime-ubuntu22.04@sha256:2d913b09e6be8387e1a10976933642c73c840c0b735f0bf3c28d97fc9bc422e0
COPY --from=ghcr.io/astral-sh/uv:0.5.1 /uv /uvx /bin/

WORKDIR /app

# Needed because LeRobot uses git-lfs.
RUN apt-get update && apt-get install -y git git-lfs linux-headers-generic build-essential clang

# Copy from the cache instead of linking since it's a mounted volume
ENV UV_LINK_MODE=copy

# Write the virtual environment outside of the project directory so it doesn't
# leak out of the container when we mount the application code.
ENV UV_PROJECT_ENVIRONMENT=/.venv

# Create venv for the project
RUN uv venv --python 3.11.9 $UV_PROJECT_ENVIRONMENT

# Copy lockfile and minimal workspace to leverage Docker layer caching for deps
COPY uv.lock pyproject.toml ./
COPY packages/openpi-client/pyproject.toml packages/openpi-client/pyproject.toml
COPY packages/openpi-client/src packages/openpi-client/src

# Install dependencies (without installing the root project yet)
RUN GIT_LFS_SKIP_SMUDGE=1 uv sync --frozen --no-install-project --no-dev

# Copy application source into the image so runtime bind mounts are unnecessary
COPY src src
COPY scripts scripts

# Include metadata files required by the build backend
COPY LICENSE README.md ./

# Install the root project into the environment now that sources are present
RUN GIT_LFS_SKIP_SMUDGE=1 uv sync --frozen --no-dev

# Copy transformers_replace files while preserving directory structure
COPY src/openpi/models_pytorch/transformers_replace/ /tmp/transformers_replace/
RUN /.venv/bin/python -c "import transformers; print(transformers.__file__)" | xargs dirname | xargs -I{} cp -r /tmp/transformers_replace/* {} && rm -rf /tmp/transformers_replace

# ------------------------------------------------------------
# Pre-download model checkpoints into the image at build time.
# This bakes the files into the container so startup is faster
# and avoids first-request downloads in production.
#
# Use a fixed cache path so it is consistent regardless of
# runtime user HOME directory.
#
# Customize with: --build-arg CHECKPOINT_PATH=gs://.../your_model
# ------------------------------------------------------------
ARG CHECKPOINT_PATH=gs://openpi-assets/checkpoints/pi05_libero
ENV OPENPI_DATA_HOME=/opt/openpi-cache
ENV CHECKPOINT_PATH=${CHECKPOINT_PATH}
RUN mkdir -p "$OPENPI_DATA_HOME" && \
    /.venv/bin/python - <<'PY'
import os
import sys
import traceback
import openpi.shared.download as download

url = os.environ.get('CHECKPOINT_PATH', 'gs://openpi-assets/checkpoints/pi05_libero')
print(f"[openpi] Pre-downloading checkpoint: {url}")
try:
    path = download.maybe_download(url)
except Exception as e:
    print(f"[openpi] Standard download failed: {e}. Retrying as anonymous...")
    try:
        path = download.maybe_download(url, gs={"token": "anon"})
    except Exception:
        traceback.print_exc()
        raise
print(f"[openpi] Checkpoint cached at: {path}")
PY

# Default listening port; overridable at runtime via `-e PORT=...`.
ENV PORT=8000

CMD /bin/bash -c "uv run scripts/serve_policy.py --port ${PORT} --env LIBERO"
