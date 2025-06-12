# run
FROM ubuntu:22.04 AS cpp_install

RUN export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y apt-transport-https autoconf bash-completion bsdmainutils
RUN export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y lldb llvm netcat ninja-build iputils-ping software-properties-common tar texinfo unzip valgrind xclip zip zlib1g-dev
RUN export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y build-essential ca-certificates clang clang-tools
RUN export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y parallel file pkg-config libssl-dev  clang-format
RUN export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y cmake curl file gdb gnupg-agent
RUN export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y libblas-dev libgraphviz-dev
RUN export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y jq htop linux-tools-common linux-tools-generic

ENV CPP_PKG=/opt/arm64.dev.cpp.22.04.tar.gz
RUN apt list --installed|awk -F"/" '{print $1}'|parallel dpkg -L :::|sort|uniq|xargs file|grep -v "directory"|sed -e 's/:/ /g'|awk '{print $2, " ", $1}' |sort |uniq|grep -v "^SVG " |grep -v "^PNG " |grep -v "^PDF" |grep -v "^broken" |grep -v "cannot"|grep -v "^directory" |grep -iv "copyright"|grep -v "changelog.Debian.gz" |awk '{print $2}' |sort |tar czf $CPP_PKG -T -


FROM ubuntu:22.04 AS rust_install

ENV CPP_PKG=/opt/arm64.dev.cpp.22.04.tar.gz
COPY --from=cpp_install $CPP_PKG $CPP_PKG

ENV RUSTUP_HOME=/root/.rustup \
    CARGO_HOME=/root/.cargo \
    RUST_BIN=/root/.cargo/bin \
    PATH=/root/.cargo/bin:$PATH \
    ARCH=aarch64-unknown-linux-gnu \
    RUST_VERSION=1.87.0

RUN tar zxf $CPP_PKG -C /
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

RUN curl -L https://github.com/rust-lang/rust-analyzer/releases/latest/download/rust-analyzer-$ARCH.gz | gunzip -c - > $RUST_BIN/rust-analyzer; \
    chmod +x $RUST_BIN/rust-analyzer
RUN cargo install wasm-pack cargo-generate wasm-bindgen-cli

ENV RUST_PKG=/opt/arm64.dev.rs.22.04.tar.gz
RUN find {$RUSTUP_HOME,$CARGO_HOME}|xargs file|grep -v "directory"|sed -e 's/:/ /g'|awk '{print $1}'|sort|uniq|tar czf $RUST_PKG -T - 

# WORKDIR /root
# RUN curl -LsSf https://astral.sh/uv/install.sh | sh
# RUN uv venv --python 3.12.8
# COPY requirements.py312.txt /root/.local/requirements.py312.txt
# RUN uv pip install -r /root/.local/requirements.py312.txt
# RUN uv pip install setuptools jq matplotlib jupyter notebook ipywidgets jupyterlab-rise jupyter-lsp jupyterlab-lsp jedi-language-server seaborn prettytable az-cli
# RUN mkdir /root/.jupyter \
#     && echo "c.ServerApp.token = ''" > /root/.jupyter/jupyter_notebook_config.py


