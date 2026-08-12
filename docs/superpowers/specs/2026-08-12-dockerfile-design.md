# Dockerfile for SecureVibes — Design

## Goal

Provide a `Dockerfile` (repo root) that packages `securevibes` so a scan can be
run immediately after `docker run`, matching the CLI usage already documented
in `README.md` (`securevibes scan .`). The Anthropic API key is supplied only
at `docker run` time — never baked into the image.

## Image contents & build

- Base image: `python:3.12-slim` (repo requires Python >=3.10).
- System packages: `git`, `ca-certificates`.
  - `git` is required because `pr-review`/`catchup` shell out to it
    (`packages/core/securevibes/scanner/state.py`,
    `packages/core/securevibes/diff/extractor.py`).
  - `ca-certificates` is required for HTTPS calls to the Anthropic API.
- No Node.js/npm install step: `claude-agent-sdk>=0.1.16` (pinned in
  `packages/core/pyproject.toml`) bundles the Claude Code CLI itself
  (`docs/references/claude-agent-sdk-guide.md`, "Claude Code CLI is now
  automatically bundled with the package").
- Install `securevibes` from this repo's local source:
  `COPY packages/core/ ./packages/core/` then `pip install ./packages/core`.
  This always matches the checked-out code (including unreleased changes),
  consistent with the "latest version" install path in `README.md`.
- Pre-init: `git config --global --add safe.directory '*'` baked into the
  image. Without this, git refuses to operate on the bind-mounted
  `/workspace` (owned by a different UID than the container) with a "dubious
  ownership" error on the very first `pr-review`/`catchup` run.
- `.dockerignore` added at repo root excluding `.git`, `docs/`, `ops/`,
  `packages/core/tests/`, `__pycache__/`, `.venv/`, etc., to keep the build
  context small.

## Runtime interface

- `WORKDIR /workspace`.
- `ENTRYPOINT ["securevibes"]`, `CMD ["--help"]`.
  - `docker run <image>` → shows CLI help.
  - `docker run ... <image> scan /workspace` → runs a scan immediately.
- The code to scan is bind-mounted at `/workspace`:
  ```bash
  docker run --rm \
    -e ANTHROPIC_API_KEY="sk-ant-..." \
    -v "$PWD:/workspace" \
    securevibes scan /workspace
  ```
  This is the containerized equivalent of `securevibes scan .` from the
  README. Scan artifacts (`.securevibes/scan_report.md`, etc.) are written
  under the scanned path, so they land directly on the host via the mount —
  no extra output volume needed.
- `ANTHROPIC_API_KEY` is passed only via `-e` at `docker run` time. It is
  never written into the image, a build arg, or any committed file.
- Runs as root inside the container (no non-root user). Bind-mount UID/GID
  friction is avoided, and the README already frames running scans in an
  isolated container as the security boundary — this doesn't weaken that.

## Documentation

Add a "Docker" section to `README.md` covering:
1. Build: `docker build -t securevibes .`
2. Get an API key: console.anthropic.com → sign in → API Keys → Create Key
   (copy the `sk-ant-...` value, treat it like a password).
3. Run a scan: the bind-mount command above.
4. Passing through optional env vars (`SECUREVIBES_MAX_TURNS`,
   per-agent `SECUREVIBES_*_MODEL` overrides, `SECUREVIBES_PR_REVIEW_*`) via
   additional `-e` flags, since they follow the same env-var config already
   documented for non-Docker use.
5. `pr-review`/`catchup` usage note: these require the mounted directory to
   be a git repo with the relevant history present (shallow clones may not
   have base commits for `--base`/`--range` comparisons).

## Out of scope

- Publishing the image to a registry.
- Non-root user / UID mapping.
- Multi-stage build optimization (single-stage is sufficient — pure-Python
  dependencies, no compiled extensions to strip).
- docker-compose.
