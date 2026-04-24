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
