# ---- Build stage: install deps into a venv ---------------------------------
FROM python:3.12-slim AS build

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .
RUN pip install --upgrade pip && pip install -r requirements.txt

# ---- Runtime stage: minimal, non-root -------------------------------------
FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    PORT=8080

# Create an unprivileged user (uid/gid 10001) to run the app.
RUN groupadd -g 10001 appuser && \
    useradd -m -u 10001 -g appuser -s /usr/sbin/nologin appuser

COPY --from=build /opt/venv /opt/venv
WORKDIR /app
COPY --chown=appuser:appuser app.py .
COPY --chown=appuser:appuser templates ./templates
COPY --chown=appuser:appuser static ./static

USER 10001
EXPOSE 8080

# gunicorn: 2 workers x 4 threads is a sane default for I/O-bound Flask.
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--threads", "4", \
     "--timeout", "30", "--access-logfile", "-", "app:app"]
