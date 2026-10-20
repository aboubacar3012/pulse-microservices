# Image toujours linux/amd64 (nodes K8s), même depuis un Mac arm64.

# --- deps ---
FROM --platform=linux/amd64 python:3.12-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# --- runtime ---
FROM --platform=linux/amd64 python:3.12-slim
WORKDIR /app

RUN useradd -r -u 10001 -m app

COPY --from=builder /install /usr/local
COPY worker.py .

USER app
CMD ["python", "-u", "worker.py"]
