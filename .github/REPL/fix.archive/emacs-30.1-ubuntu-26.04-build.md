# Emacs 30.1 Ubuntu 26.04 build

Measured on C01 on 2026-09-14.

## Target

- Distro: Ubuntu 26.04 LTS
- glibc: `2.43-2ubuntu2.4`
- Architecture: `linux/amd64`
- Docker base: `ubuntu:26.04`
- Docker base digest:
  `sha256:513c074113a871b51a8d16ab445c88779d6452d937a164fb5cc479f32668a41d`
- Source tree: `/workspace/dot-emacs`
- Recovered source HEAD:
  `353ad0578a11906854e1380b7fe2cc15b2df0d24`

## Why the existing 24.04 bundle is not the WSL artifact

The existing builder
`build/emacs-30.1-treesitter-ubuntu-24.04` uses Ubuntu 24.04/glibc
2.39 and its explicit tar list includes `libc.so.6` plus other
versioned runtime libraries. Extracting that root-level artifact onto
Ubuntu 26.04 crosses a glibc boundary and can replace a coherent 2.43
runtime with a mixed 2.39/2.43 loader stack.

C01 demonstrated the failure mode:

```text
undefined symbol: __nptl_change_stack_perm, version GLIBC_PRIVATE
```

`GLIBC_PRIVATE` symbols have no cross-release compatibility contract.
The WSL artifact must therefore be built from an Ubuntu 26.04 image and
validated in a separate fresh Ubuntu 26.04 container.

## Recipe constraints

- Create a self-contained sibling:
  `build/emacs-30.1-treesitter-ubuntu-26.04`.
- Leave the proven 24.04 builder unchanged.
- Keep these pins unchanged:
  - Emacs `30.1`
  - tree-sitter `v0.24.7`
  - emacs-libvterm commit
    `54c29d14bca05bdd8ae60cda01715d727831e3f9`
- Build only in Docker; do not compile on the WSL host.
- Produce a root-extractable artifact named
  `amd64.emacs30.1_26.04.tar.gz`.
- Generate the 26.04 runtime-library manifest from the built image.
  Do not copy the 24.04 version-suffixed library list blindly.
- The build-side and validation-side `ldd --version | head -1` values
  must both report glibc 2.43.

## Required separate-container validation

1. Start a fresh `ubuntu:26.04` container.
2. Record its base glibc package/version and checksums for the loader,
   `libc.so.6`, and `libm.so.6`.
3. Extract the artifact at `/`.
4. Run `ldconfig`.
5. Verify the loader/libc/libm remain a coherent Ubuntu 26.04 set.
6. Verify:
   - `emacs --version` reports GNU Emacs 30.1;
   - batch evaluation reports `30.1`;
   - `(require 'vterm)` succeeds;
   - the Emacs binary and vterm module are `x86-64`;
   - no `aarch64` paths or binaries appear in the artifact.

## Recovery prerequisite now satisfied

C01 was re-imported as a clean Ubuntu 26.04 distro before this build.
The production distro is named `Ubuntu`, its hostname is `c01wsl`, and
SSH listens on port 2200. The damaged distro and temporary
`UbuntuClean` registration were removed only after validation.

The clean rollback export remains at:

```text
C:\Temp\UbuntuClean-final-20260914.tar
bytes=3942082560
sha256=A67ADB4EF4CA1E223A0F5F4464705E7DB26994DA2F0EC15AADC425252FF35619
```

## Compiler gate

Measured in the exact `ubuntu:26.04` image:

| package | candidate |
|---|---|
| `gcc-14` | `14.3.0-14ubuntu1` |
| `libgccjit0` | `14.3.0-14ubuntu1` |
| `libgccjit-14-dev` | `14.3.0-14ubuntu1` |
| `gcc-15` | `15.2.0-16ubuntu1` |
| `libgccjit-15-dev` | `15.2.0-16ubuntu1` |

The Ubuntu 24.04 recipe's `gcc-10` and `libgccjit-10-dev` have no
candidate in 26.04. The 26.04 builder uses the coherent
`gcc-14`/`libgccjit0`/`libgccjit-14-dev` set because `libgccjit0`
resolves to the same 14.3.0 package version. This is the smallest
version-only adaptation that preserves native compilation.

## Artifact safety improvement

The 26.04 manifest must not ship the target's core glibc loader files:

```text
libc.so.6
libm.so.6
ld-linux-x86-64.so.2
```

Emacs should dynamically use the coherent glibc already installed on
the Ubuntu 26.04 target. The separate-container smoke test must assert
that extracting the artifact does not change the target checksums for
those files.

## Completed build

Completed on the rebuilt x86_64 Ubuntu 26.04 WSL host on 2026-09-14.
Compilation ran only inside Docker.

```text
image:
  caapi/amd64.emacs30.1:26.04
  sha256:266d97645d08f39acad6168cd0c72bf12ebe7df2c77af3634ec408b168a1ec2f
  architecture: amd64
  size: 3313586545 bytes

base:
  ubuntu@sha256:513c074113a871b51a8d16ab445c88779d6452d937a164fb5cc479f32668a41d

manifest:
  amd64.tar.list
  entries: 13735

artifact:
  amd64.emacs30.1_26.04.tar.gz
  size: 403028464 bytes
  sha256: afe0006f3cd68d096b9ec2075b649d2b67500c2b2fff2d91515c46af3391ee7f
```

The artifact is generated locally and ignored by Git because it exceeds
GitHub's normal file-size limit. Reproduce it from the committed builder.

## Build, package, and verify

Run the build and package commands in one shell:

```bash
cd build/emacs-30.1-treesitter-ubuntu-26.04
./build.sh
./refresh-amd64-tar-list.sh
./pack.sh
sha256sum amd64.emacs30.1_26.04.tar.gz
```

Run verification in a separate shell:

```bash
cd build/emacs-30.1-treesitter-ubuntu-26.04
./verify.sh amd64.emacs30.1_26.04.tar.gz
```

The completed smoke test printed:

```text
GNU Emacs 30.1
jq-1.8.1
EMACS_26_04_VERIFY_OK
```

The build image reported glibc `2.43-2ubuntu2.4`; the clean validation
container reported glibc `2.43-2ubuntu2.3`. This patch-level difference is
safe because the artifact contains none of the target's core loader,
`libc.so.6`, or `libm.so.6`. Their checksums were unchanged by root
extraction, and every Emacs and jq dependency resolved after `ldconfig`.

The final package also verified:

- Emacs 30.1 and vterm are x86-64;
- native compilation and tree-sitter are available;
- tree-sitter remains pinned to `v0.24.7`;
- emacs-libvterm remains pinned to
  `54c29d14bca05bdd8ae60cda01715d727831e3f9`;
- `jq=1.8.1-4ubuntu2` and its `libjq`/`libonig` runtime closure are present;
- `/root/.bashrc` uses `http://127.0.0.1:11434/v1`;
- no global `COPILOT_MODEL` is set;
- `ghe` selects GitHub `gpt-5.6-sol` with high effort and long context;
- `h()` selects a model dynamically from the provider catalog.
