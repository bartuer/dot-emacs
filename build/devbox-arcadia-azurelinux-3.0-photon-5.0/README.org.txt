* Purpose
  Build and package a minimal "dev.base" toolset for the "arcadia" base
  (non-Ubuntu), targeting OfficePy devcontainer base image:
  - mcr.microsoft.com/officepy/codeexecutionjupyterext1

  Output artifact:
  - amd64.arcadia.dev.base.azl3.0.tar.gz

* Notes
  - This should contain runtime tools you want available everywhere.
  - Avoid dpkg/apt; use Arcadia package manager (likely tdnf).
  - The tarball must be extractable at filesystem root ("tar ... -C /").

* Files
  - Dockerfile     : installs base packages
  - tar.sh         : creates tarball inside container
  - pack.sh        : helper to run tar.sh inside built image

* Suggested workflow
  1) docker build -t mcr.microsoft.com/officepy/codeexecutionjupyterext1:dev.base.arcadia .
  2) ./pack.sh

  The tarball should appear in this directory as:
  - amd64.arcadia.dev.base.azl3.0.tar.gz

* Persisting Copilot CLI state
  Copilot CLI (ghcp CLI) writes session DB, checkpoints, plans,
  auth/config, and its vendored node pkg into ~/.copilot.  The full
  folder layout is captured for reference at:
    (link "../../.github/REPL/fix.archive/emacs_ghcp/container.copilot_folder.txt" 1)

  Mount a host directory onto /root/.copilot so the data survives
  `docker rm`:

    mkdir -p $HOME/.copilot-arcadia
    docker run -d --name arcadia \
      -v $HOME/.copilot-arcadia:/root/.copilot \
      -v $HOME/.ssh:/root/.ssh:ro \
      mcr.microsoft.com/officepy/codeexecutionjupyterext1:dev.base.arcadia

  A convenience wrapper is provided in this folder:
  - run-container.sh    host-side, bakes in the bind-mount
    (not shipped in the tarball)

  Notes:
  - install.amd64.sh (shipped inside the tarball) warns at install
    time if /root/.copilot is NOT a bind-mount.
  - Ownership inside the container is uid 0 (root); the host dir
    must be writable by root, or uid mapping must align.
  - pkg/ under ~/.copilot is redownloadable but keeping it inside
    the bind mount simplifies first-run bootstrap.

* LLM endpoints
  The shipped /root/.bashrc hard-codes sensible defaults for every
  standard LLM SDK, pointing them at http://localhost:11434
  (Ollama's default). Values use the `${VAR:=default}` idiom so any
  value you pass via `docker run -e VAR=...` wins:

    OPENAI_BASE_URL=http://localhost:11434/v1   OPENAI_API_KEY=dummy
    ANTHROPIC_BASE_URL=http://localhost:11434/anthropic   ANTHROPIC_API_KEY=dummy
    OLLAMA_HOST=http://localhost:11434
    COPILOT_MODEL_BASE_URL=http://localhost:11434

  To point at something else (relay, hosted endpoint, etc.):

    docker run -d --name arcadia \
      -e OPENAI_BASE_URL=https://my-relay.example/v1 \
      -e OPENAI_API_KEY="$MY_TOKEN" \
      ...
      mcr.microsoft.com/officepy/codeexecutionjupyterext1:dev.base.arcadia
