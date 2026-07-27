# Copilot Instructions — `dot-emacs` build & packaging workspace

> This repo (`bartuer/dot-emacs`, remote `github:bartuer/dot-emacs.git`) is a
> personal Emacs configuration **plus** a set of Docker-based builders under
> `build/` whose one job is to **compile Emacs 30.1 (+ tree-sitter + vterm) and
> a companion "devbox" toolchain for a target platform (arch × OS), then
> package the result into relocatable `*.tar.gz` artifacts that install with
> `tar -zxf <artifact>.tar.gz -C /` on the target machine.** Plans live under
> `.github/REPL/` and are authored/executed with the `org_plan` / `exec_plan`
> skills.

---

## HARD RULES (read every session)

1. **Docker is the build platform. Never compile Emacs/toolchains on the host.**
   Every builder lives in its own `build/<flavor>/` folder with a `Dockerfile`;
   the image compiles everything to a staging prefix inside the container. The
   host only drives `docker build` / `docker run` and receives the tarball.

2. **The packaging contract is "extract at root".** Every artifact is a
   `tar czf … -C /` tarball built from an explicit file list (`*.tar.list`) or a
   `dpkg -L | file`-derived list. It MUST be installable on the target with
   `tar -zxf <artifact>.tar.gz -C /` and nothing else. Preserve absolute paths
   (`root/local`, `usr/local/lib`, `lib/<triplet>`, `bin/entry`, …). Do not
   introduce a tarball that assumes a non-root extraction point.

3. **Build for the platform you name — arch AND os must match end to end.**
   `--platform linux/amd64` ⇒ `x86_64-linux-gnu` lib paths ⇒ `amd64.*` artifact
   name; `--platform linux/arm64` ⇒ `aarch64-linux-gnu` lib paths ⇒ `arm64.*`
   artifact name. An `arm64.tar.list` must contain **zero** `x86_64-linux-gnu`
   entries (and vice-versa). Apple-Silicon macOS runs the `linux/arm64`
   artifact inside Docker Desktop's Linux VM — same arm64 tarball, so a single
   arm64 build serves both "mac" (Docker VM) and native arm Linux.
   A non-native arch is produced by `docker buildx build --platform …` via
   QEMU/binfmt emulation (e.g. an x86_64 WSL host cross-building `linux/arm64`);
   it yields genuine target-arch binaries, just slower.

3a. **One flavor = one self-contained folder with its OWN Dockerfile.** Each
   `build/<flavor>/` owns a reviewable `Dockerfile` plus its build/pack/install
   scripts. **Do NOT bolt a second architecture's scripts onto an existing
   arch's folder** — give the new arch its own sibling folder (naming:
   `<flavor>-arm64`, e.g. `emacs-30.1-treesitter-ubuntu-24.04-arm64/`,
   `devbox-ubuntu-24.04-arm64/`). Seed it by copying the (arch-agnostic)
   Dockerfile + support files from the amd64 sibling, then add the arm64
   scripts and switch any baked artifact/name references (`amd64.*`→`arm64.*`,
   `install.amd64.sh`→`install.arm64.sh`). Leave the amd64 folder untouched so
   each folder's Dockerfile can be reviewed independently.

4. **NEVER auto-install a dependency or bump a pinned version silently.**
   Before any new `apt-get install` / `pip install` / `npm i -g` / git tag bump
   in a Dockerfile, state package + version + why and confirm with the user.
   Two pins are load-bearing and MUST NOT drift without discussion:
   - `TREE_SITTER_TAG=v0.24.7` — Emacs 30.1 `treesit.c` uses `ts_language_version`,
     renamed in tree-sitter 0.25; newer tags break the build.
   - `EMACS_LIBVTERM_COMMIT` (pinned SHA) — vterm module ABI must match the
     Emacs source tree it is compiled against.

5. **Reproducible + verifiable.** A build must be re-runnable from a clean
   checkout with no manual steps, and every artifact must have a read-only
   smoke test (see "Verify"). Run the build in one shell and the verify/smoke
   test in a SEPARATE shell/container — never in the build shell.

6. **NEVER commit secrets.** SSH private keys, PATs, proxy creds stay out of the
   repo. `authorized_keys` / `config` in a builder folder are public-key / host
   aliases only. Durable findings go to `.github/REPL/fix.archive/` (no secrets).

---

## The build → pack → install pipeline (the core loop)

Each `build/<flavor>/` folder is a self-contained builder. Using the reference
flavor `build/emacs-30.1-treesitter-ubuntu-24.04/`:

```
  ┌ 1. BUILD image (compile inside container) ────────────────────────────┐
  │  build.macos.2.amd.sh  →  docker buildx build --platform linux/amd64 \ │
  │      --build-arg https_proxy=… . -t caapi/amd64.emacs30.1:24.04        │
  │  (Dockerfile: apt deps → tree-sitter v0.24.7 → emacs-30.1 (native-comp)│
  │   → clone bartuer/dot-emacs → emacs-libvterm module → stage under /)   │
  └───────────────────────────────────────────────────────────────────────┘
  ┌ 2. PACK (tar the explicit file list inside the image) ─────────────────┐
  │  pack.sh → docker run -w / -v ${PWD}:/opt <image> /opt/tar.sh          │
  │  tar.sh  → tar czf /opt/<arch>.emacs30.1_24.04.tar.gz \                │
  │              --exclude=root/etc/el/.git -T /opt/<arch>.tar.list        │
  └───────────────────────────────────────────────────────────────────────┘
  ┌ 3. INSTALL on target (relocatable, root extraction) ───────────────────┐
  │  install.<arch>.sh → tar zxf <arch>.emacs30.1_24.04.tar.gz -C / ; \    │
  │                       … other dev.*.tar.gz … ; ldconfig ; . ~/.bashrc  │
  └───────────────────────────────────────────────────────────────────────┘
```

The **devbox** builder (`build/devbox-ubuntu-24.04/`) is the toolchain companion:
a multi-stage Dockerfile produces per-language `dev.<cc|rs|js|py|cs|base>.tar.gz`
packs, each generated by `apt list --installed | dpkg -L | file | tar -T -`
rather than a hand-written `*.tar.list`. `install.<arch>.sh` unpacks the emacs
tarball first, then the dev packs.

### Key files per builder (names are conventional)
- `Dockerfile`                — compiles + stages everything (the source of truth)
- `<arch>.tar.list`           — explicit, deterministic file manifest to package
- `tar.sh`                    — runs `tar czf … -T <arch>.tar.list` INSIDE container
- `pack.sh`                   — `docker run … /opt/tar.sh` to emit the tarball
- `build.macos.2.amd.sh` / `build.macos.sh` — CROSS-build via `docker buildx build --platform …` (host≠target)
- `build.*.native.sh`        — NATIVE build via plain `docker build` (host==target; no qemu), guards `uname -m`
- `run.sh` / `run.dev.sh`     — start a container from the built image (dev/ssh)
- `install.<arch>.sh`         — `tar zxf … -C /` on the target
- `copy.<arch>.sh`            — copy built `*.so` (tsc-dyn, grammars) back into repo
- `entry.sh`, `.bashrc`, `config`, `authorized_keys` — baked into the image

---

## Flavor map (what exists under `build/`)

| folder                                                  | base            | arch built        | artifact prefix                          |
|---------------------------------------------------------|-----------------|-------------------|------------------------------------------|
| `emacs-30.1-treesitter-ubuntu-24.04`                    | ubuntu:24.04    | amd64             | `amd64.emacs30.1_24.04.tar.gz`           |
| `emacs-30.1-treesitter-ubuntu-24.04-arm64`              | ubuntu:24.04    | arm64 (buildx)    | `arm64.emacs30.1_24.04.tar.gz`           |
| `devbox-ubuntu-24.04-arm64`                             | ubuntu:24.04    | arm64 (buildx)    | `arm64.dev.<base\|cc\|rs\|js\|py\|cs>.24.04.tar.gz` |
| `emacs-30.1-treesitter-ubuntu-22.04`                    | ubuntu:22.04    | amd64 & arm64     | `<arch>.emacs30.1_22.04.tar.gz`          |
| `emacs-29.1-treesitter-ubuntu-20.04`                    | ubuntu:20.04    | amd64 & arm64     | `<arch>.emacs30.1_20.04.tar.gz`          |
| `emacs-30.1-treesitter-arcadia-azurelinux-3.0-photon-5.0` | AzureLinux 3.0 (tdnf) | amd64     | `amd64.arcadia.emacs30.1_azl3.0.tar.gz`  |
| `devbox-ubuntu-24.04`                                   | ubuntu:24.04    | amd64             | `amd64.dev.<cc\|rs\|js\|py\|cs\|base>.24.04.tar.gz` |
| `devbox-ubuntu-22.04`                                   | ubuntu:22.04    | amd64 & arm64     | `<arch>.dev.*.22.04.tar.gz`              |
| `devbox-arcadia-azurelinux-3.0-photon-5.0`              | AzureLinux 3.0  | amd64             | `amd64.arcadia.dev.base.azl3.0.tar.gz`   |

- The **22.04 flavor is the working reference for arm64** (`build.macos.sh` uses
  `--platform linux/arm64`, and both `emacs` and `devbox` have `arm64.tar.list` /
  arm install scripts). Port its arm64 approach when adding arm64 to 24.04.
- **Arcadia/AzureLinux ≠ Ubuntu**: no apt/dpkg — use `tdnf`/`rpm`; `libgccjit`
  and prebuilt tree-sitter are unavailable (build from source, no native-comp).

---

## Cross-arch / macOS build notes (Docker Desktop)

- **FIRST: check host arch vs target arch (`uname -m`).** The target is encoded
  in the folder name (`…-arm64` ⇒ target arm64; no suffix / `amd64` ⇒ amd64).
  - **Host arch == target arch ⇒ build NATIVELY. Do NOT cross-build.** Use a
    plain `docker build -f Dockerfile.base . -t <img>` — no `--platform`, no
    `buildx`, no qemu/binfmt. It is genuine target-arch output and much faster.
    Example: on a native aarch64 host, build the arm64 devbox with
    `build/devbox-ubuntu-24.04-arm64/build.base.native.sh` (guards host==target).
  - **Host arch != target arch ⇒ cross-build** with
    `docker buildx build --platform linux/<target>` (QEMU/binfmt emulation).
    That is what `build.macos.sh` does (x86_64/Intel-mac or WSL host → arm64).
    Register binfmt once if needed: `docker run --privileged --rm tonistiigi/binfmt --install <arch>`.
- Apple-Silicon Macs build arm64 with `docker buildx build --platform linux/arm64`;
  Intel Macs / amd64 hosts build `--platform linux/amd64`. `buildx` cross-builds
  either way, but native-arch is much faster (use `caffeinate` on macOS to keep
  the long native-comp build awake — see `devbox-ubuntu-22.04/build.macos.sh`).
- Corp-net builds route git/curl through a SOCKS proxy:
  `--build-arg https_proxy=socks5://host.docker.internal:8080`, and the baked
  `~/.ssh/config` sets `ProxyCommand nc -X 5 -x host.docker.internal:8080 %h %p`.
  On a direct-internet Linux host, drop the proxy arg (the Dockerfile's git-proxy
  line is already commented out).
- `--platform` must be passed to BOTH `docker build` and the later `docker run`
  (pack/run) so the packaged libs match the intended arch.

### Pushing to GitHub over SSH

You can `git push` to GitHub directly over SSH (no HTTPS/PAT needed). Convention:

```bash
git remote set-url origin git@github.com:bartuer/dot-emacs.git
git push origin HEAD          # authenticated via ~/.ssh/nx.rsa
```

The baked `~/.ssh/config` already defines a `Host github` alias
(`HostName github.com`, `User git`, `IdentityFile ~/.ssh/nx.rsa`), so
`git@github.com` resolves to that identity. The key is `~/.ssh/nx.rsa`
(its public half must be registered on the GitHub account for pushes to
succeed). On corp-net the same `config` routes GitHub SSH through the SOCKS
proxy via `ProxyCommand nc -X 5 -x host.docker.internal:8080 %h %p`.

---

## Verify (read-only smoke tests, run in a SEPARATE container/shell)

After installing a freshly built tarball into a clean base container
(`docker run --platform linux/<arch> -v $PWD:/opt <base> bash` → `install.<arch>.sh`):

```bash
emacs --version | head -1                      # prints "GNU Emacs 30.1"
emacs --batch --eval '(princ emacs-version)'   # native-comp smoke
emacs --batch \
  --eval '(add-to-list (quote load-path) "/root/etc/el/vendor/vterm")' \
  --eval '(require (quote vterm))' \
  --eval '(message "VTERM OK")'                # vterm module loads
file $(command -v emacs) | grep -qi aarch64    # arch sanity for arm64 builds
```
Devbox packs: `git --version`, `node --version`, `python --version`,
`cargo --version` (whichever packs were installed). Arch sanity: no
`x86_64-linux-gnu` paths inside an arm64 tarball (`tar tzf … | grep x86_64`
must be empty).

---

## Plans & skills (how work is organized here)

- Plans live at `.github/REPL/NN.<slug>.org.txt` (Org-mode "executable" docs).
- **Author** a plan with the `org_plan` skill; **execute** one with `exec_plan`.
  The canonical driving prompt is `.github/prompts/master.prompt.md`.
- Plan-doc discipline: `* Goal` (final checklist) → `* Dependencies` → `* Context`
  → `* Main Loop :test_tool:` (R-E-P-L). Work items are `- [ ]` / `- [X]`; groups
  are `* TODO|DONE|ABORT|HALT <title>`. Local file anchors use
  `(link "/abs/path" <approx-char-offset>)`. `:test_tool:` marks the verify tool;
  **never run the test and the build target in the same shell.**
- Durable findings (build recipes, ABI postmortems) → a short-named file under
  `.github/REPL/fix.archive/`; commit it, no secrets.

## Source-of-truth references
- Reference builder (amd64): `build/emacs-30.1-treesitter-ubuntu-24.04/Dockerfile`
- arm64 reference (working): `build/emacs-30.1-treesitter-ubuntu-22.04/` (`build.macos.sh`, `arm64.tar.list`, `tar.sh`)
- Devbox multi-stage packs: `build/devbox-ubuntu-24.04/Dockerfile`, `pack.sh`, `install.amd64.sh`
- Arcadia (non-apt) pattern: `build/emacs-30.1-treesitter-arcadia-azurelinux-3.0-photon-5.0/README.org.txt`
- Top-level build journal: `build/project.org.txt`
- Plans dir: `.github/REPL/`  · Skills: `.github/skills/{org_plan,exec_plan}/`
