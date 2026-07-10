# Build context is the cmpys/ project root (so prompts/ — a sibling of
# backend/ — can be copied). Build with:
#   docker build -f backend/Dockerfile -t <tag> .   (run from cmpys/)
FROM python:3.11-slim AS base
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends libpq5 curl \
    && rm -rf /var/lib/apt/lists/*
COPY backend/requirements.txt .
RUN pip install -r requirements.txt
COPY backend/ /app/
# Prompts live as a sibling of backend/ in the repo. PROMPTS_DIR resolves to
# /prompts in the container (five parents up from prompt_loader.py), so they
# must land there.
COPY prompts/ /prompts/
RUN chmod +x docker-entrypoint.sh
EXPOSE 8000
ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["web"]
