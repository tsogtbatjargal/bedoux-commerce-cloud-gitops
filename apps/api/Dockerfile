# syntax=docker/dockerfile:1
FROM docker.io/library/python:3.12-slim AS builder

WORKDIR /build
COPY pyproject.toml ./
COPY app ./app

RUN pip install --no-cache-dir --prefix=/install .

FROM docker.io/library/python:3.12-slim AS runtime

RUN groupadd --gid 10001 bedoux && \
    useradd --uid 10001 --gid bedoux --no-create-home --shell /usr/sbin/nologin bedoux

COPY --from=builder /install /usr/local
COPY app /app/app
COPY migrations /app/migrations
COPY alembic.ini /app/alembic.ini

WORKDIR /app
USER bedoux

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2)" || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
