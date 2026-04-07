* Purpose
  Build and package Emacs 30.1 (+ optional tree-sitter) for the "arcadia" base
  (non-Ubuntu), targeting OfficePy devcontainer base image:
  - mcr.microsoft.com/officepy/codeexecutionjupyterext1

  Output artifact:
  - amd64.arcadia.emacs30.1_azl3.0.tar.gz

* Notes
  - This folder mirrors the ubuntu builders but must not assume apt/dpkg.
  - Prefer tdnf/rpm workflow (Arcadia/AzureLinux style).
  - The tarball must be extractable at filesystem root ("tar ... -C /").

* Files
  - Dockerfile          : build image that compiles + installs to a staging prefix
  - amd64.tar.list      : explicit file list to package (recommended; deterministic)
  - tar.sh              : creates tarball inside container
  - pack.sh             : helper to run tar.sh inside the built image

* Suggested workflow
  1) docker build -t mcr.microsoft.com/officepy/codeexecutionjupyterext1:emacs30.1.arcadia .
  2) ./pack.sh

  The tarball should appear in this directory as:
  - amd64.arcadia.emacs30.1_azl3.0.tar.gz
