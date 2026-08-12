# SecureVibes Dockerfile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `Dockerfile` (+ `.dockerignore`) at the repo root that builds a
container image ready to run `securevibes scan` immediately after `docker
run`, and document its usage (including how to obtain `ANTHROPIC_API_KEY`)
in `README.md`.

**Architecture:** Single-stage `python:3.12-slim` image. `securevibes` is
installed from this repo's local source (`packages/core`) at build time.
`git` + `ca-certificates` are installed via apt. `ENTRYPOINT ["securevibes"]`
makes the image behave like the CLI itself; the target codebase to scan is
bind-mounted to `/workspace`; `ANTHROPIC_API_KEY` is passed only via
`docker run -e`.

**Tech Stack:** Docker, `python:3.12-slim`, pip, apt (`git`,
`ca-certificates`), the existing `securevibes` package
(`packages/core/pyproject.toml`).

## Global Constraints

- Base image must satisfy `requires-python = ">=3.10"` (`packages/core/pyproject.toml`) — use `python:3.12-slim`.
- Install `git` and `ca-certificates` via apt — required by `pr-review`/`catchup` (git subprocess calls) and HTTPS calls to the Anthropic API.
- No Node.js/npm install step — `claude-agent-sdk>=0.1.16` bundles the Claude Code CLI (per `docs/references/claude-agent-sdk-guide.md`).
- Install `securevibes` from local source: `pip install ./packages/core` (not PyPI).
- Bake in `git config --global --add safe.directory '*'` so bind-mounted repos don't trigger git's "dubious ownership" error.
- `WORKDIR /workspace`; `ENTRYPOINT ["securevibes"]`; `CMD ["--help"]`.
- `ANTHROPIC_API_KEY` must only ever be supplied via `docker run -e ANTHROPIC_API_KEY=...` — never baked into the image, a build arg, or a committed file.
- Container runs as root (no non-root user) — documented as an accepted tradeoff for bind-mount simplicity.
- `.dockerignore` must exclude `.git`, `docs`, `ops`, `.github`, `.factory`, `packages/core/tests`, caches, and venvs.

---

### Task 1: Dockerfile + .dockerignore

**Files:**
- Create: `Dockerfile`
- Create: `.dockerignore`

**Interfaces:**
- Consumes: `packages/core/pyproject.toml` (`project.scripts.securevibes` entry point), `packages/core/` source tree.
- Produces: a local Docker image tagged `securevibes:local`, invocable as `docker run ... securevibes:local scan /workspace` — this exact invocation shape is what Task 2's README section documents.

- [ ] **Step 1: Write `.dockerignore`**

```
.git
.github
.factory
docs
ops
LICENSE
**/__pycache__
**/*.pyc
**/.pytest_cache
**/.mypy_cache
**/.venv
**/env
**/.env
packages/core/tests
packages/core/*.egg-info
packages/core/build
packages/core/dist
```

- [ ] **Step 2: Write `Dockerfile`**

```dockerfile
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
```

- [ ] **Step 3: Build the image**

Run (from the repo root, via WSL since Docker is only reachable there in this environment):

```bash
wsl -d Ubuntu -- bash -lc "cd /mnt/c/Projects/Git/securevibes && /snap/bin/docker build -t securevibes:local ."
```

Expected: build completes with `Successfully tagged securevibes:local` (or the buildkit equivalent `naming to docker.io/library/securevibes:local`), no errors.

- [ ] **Step 4: Verify default CMD shows help**

```bash
wsl -d Ubuntu -- bash -lc "/snap/bin/docker run --rm securevibes:local"
```

Expected: `securevibes` CLI help/usage text is printed (same as running `securevibes --help` outside Docker), exit code 0.

- [ ] **Step 5: Verify the package installed is this repo's local source**

```bash
wsl -d Ubuntu -- bash -lc "/snap/bin/docker run --rm --entrypoint pip securevibes:local show securevibes"
```

Expected: output includes `Name: securevibes`, `Version: 0.4.0` (matches `packages/core/pyproject.toml`), and `Editable project location` is absent (regular install, not `-e`).

- [ ] **Step 6: Verify the safe.directory pre-init against a bind-mounted repo**

```bash
wsl -d Ubuntu -- bash -lc "/snap/bin/docker run --rm -v /mnt/c/Projects/Git/securevibes:/workspace --entrypoint git securevibes:local -C /workspace status"
```

Expected: normal `git status` output (e.g. `On branch main`, clean or dirty tree) — NOT a `fatal: detected dubious ownership in repository at '/workspace'` error.

- [ ] **Step 7: Verify `scan --help` works through the mounted-workspace invocation shape**

```bash
wsl -d Ubuntu -- bash -lc "/snap/bin/docker run --rm -v /mnt/c/Projects/Git/securevibes:/workspace securevibes:local scan --help"
```

Expected: `securevibes scan` subcommand help text is printed, exit code 0. (This does not require `ANTHROPIC_API_KEY` — `--help` exits before any Claude API call.)

- [ ] **Step 8: Commit**

```bash
git add Dockerfile .dockerignore
git commit -m "feat: add Dockerfile for containerized securevibes scans"
```

---

### Task 2: README Docker section

**Files:**
- Modify: `README.md` (insert a new `## 🐳 Docker` section immediately after the existing `## 🔐 Runtime Safety Model` section — i.e. right before `## 🎯 Usage`)

**Interfaces:**
- Consumes: the exact `docker build`/`docker run` invocations verified in Task 1 (image tag `securevibes:local`, `-v $PWD:/workspace`, `-e ANTHROPIC_API_KEY=...`, `scan /workspace`).
- Produces: nothing consumed by later tasks — this is the terminal documentation task.

- [ ] **Step 1: Insert the Docker section into `README.md`**

Find this exact text in `README.md` (end of the Runtime Safety Model section):

```
For package-level details, see `packages/core/README.md`.

---

## 🎯 Usage
```

Replace it with:

```
For package-level details, see `packages/core/README.md`.

---

## 🐳 Docker

Run SecureVibes in a container — no local Python/venv setup required.

### Build the image

```bash
docker build -t securevibes .
```

### Get an Anthropic API key

Docker containers can't use the interactive `claude` / `/login` flow, so
scans inside a container authenticate with an API key:

1. Go to [console.anthropic.com](https://console.anthropic.com/) and sign in (or create an account).
2. Open **API Keys** (under Settings).
3. Click **Create Key**, name it, and copy the value (starts with `sk-ant-...`).
4. Treat it like a password — don't commit it or bake it into the image.

### Run a scan

Mount the code you want to scan to `/workspace` and pass the key via `-e`:

```bash
docker run --rm \
  -e ANTHROPIC_API_KEY="sk-ant-your-key-here" \
  -v "$PWD:/workspace" \
  securevibes scan /workspace
```

This is the containerized equivalent of `securevibes scan .`. Reports are
written under the mounted directory (e.g. `./.securevibes/scan_report.md`),
so they persist on the host after the container exits.

Any `securevibes` subcommand works the same way, e.g.:

```bash
# View CLI help
docker run --rm securevibes

# JSON report
docker run --rm -e ANTHROPIC_API_KEY="sk-ant-your-key-here" -v "$PWD:/workspace" \
  securevibes scan /workspace --format json --output results.json

# PR review (requires the mounted directory to be a full, non-shallow git checkout)
docker run --rm -e ANTHROPIC_API_KEY="sk-ant-your-key-here" -v "$PWD:/workspace" \
  securevibes pr-review /workspace --base main --head feature-branch
```

### Optional configuration

Any of the environment variables documented under
[Optional Configuration](#optional-configuration) (e.g.
`SECUREVIBES_MAX_TURNS`, `SECUREVIBES_CODE_REVIEW_MODEL`) can be passed the
same way, with additional `-e` flags:

```bash
docker run --rm \
  -e ANTHROPIC_API_KEY="sk-ant-your-key-here" \
  -e SECUREVIBES_MAX_TURNS=75 \
  -v "$PWD:/workspace" \
  securevibes scan /workspace
```

---

## 🎯 Usage
```

- [ ] **Step 2: Verify the documented commands match what Task 1 tested**

Confirm by inspection that every `docker run`/`docker build` command added in
Step 1 uses the same image behavior verified in Task 1 (Steps 3–7): default
CMD prints help, `ENTRYPOINT` is `securevibes`, `/workspace` is the mount
point, `ANTHROPIC_API_KEY` is passed via `-e` only.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document Docker build/run usage for securevibes"
```
