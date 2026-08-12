FROM python:3.12-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY packages/core/ ./packages/core/
RUN pip install --no-cache-dir ./packages/core

# Bind-mounted repos are owned by a different UID than the container;
# without this, git refuses to operate on them ("dubious ownership").
RUN git config --global --add safe.directory '*'

WORKDIR /workspace

ENTRYPOINT ["securevibes"]
CMD ["--help"]
