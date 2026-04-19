# ── Base image ──────────────────────────────────────────────────────────
# Use the official slim Python image. "slim" omits build tools and
# documentation, reducing the final image size significantly.
FROM python:3.11-slim

# ── Working directory ───────────────────────────────────────────────────
# All subsequent commands run from /app inside the container.
# This is also where the application files will live.
WORKDIR /app

# ── Install dependencies first (layer caching) ─────────────────────────
# Copy requirements.txt before the application code. Docker caches each
# layer. If requirements.txt hasn't changed, this pip install layer is
# reused from cache — making rebuilds after code changes much faster.
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ── Copy application files ──────────────────────────────────────────────
# model.pkl and main.py are copied after dependencies. This preserves
# the cache benefit above — a code-only change doesn't re-run pip.
COPY app/main.py .
COPY app/model.pkl .

# ── Expose the application port ─────────────────────────────────────────
# This is documentation for Docker — it does not actually publish the
# port. Port binding happens at `docker run` time with -p.
EXPOSE 8000

# ── Start the application ───────────────────────────────────────────────
# Uvicorn is the ASGI server. It runs main.py and binds to all interfaces
# so the container port is reachable from the host.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
