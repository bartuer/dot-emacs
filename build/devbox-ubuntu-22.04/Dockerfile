FROM ubuntu:22.04 AS cpp_install

RUN export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y apt-transport-https autoconf bash-completion bsdmainutils lldb llvm netcat ninja-build iputils-ping software-properties-common tar texinfo unzip valgrind xclip zip zlib1g-dev build-essential ca-certificates clang clang-tools parallel file pkg-config libssl-dev  clang-format cmake curl file gdb gnupg-agent libblas-dev libgraphviz-dev jq htop linux-tools-common linux-tools-generic ca-certificates

ENV CPP_PKG=/opt/arm64.dev.cpp.22.04.tar.gz
RUN apt list --installed|awk -F"/" '{print $1}'|parallel dpkg -L :::|sort|uniq|xargs file|grep -v "directory"|sed -e 's/:/ /g'|awk '{print $2, " ", $1}' |sort |uniq|grep -v "^SVG " |grep -v "^PNG " |grep -v "^PDF" |grep -v "^broken" |grep -v "cannot"|grep -v "^directory" |grep -iv "copyright"|grep -v "changelog.Debian.gz" |awk '{print $2}' |sed '$a /etc/ssl/certs'|sed '$a /etc/alternatives'|sed '$a /usr/bin'|sort |uniq|tar czf $CPP_PKG -T -

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

RUN curl -k  -sSf https://sh.rustup.rs | sh -s -- -y
RUN cargo install wasm-pack cargo-generate wasm-bindgen-cli

RUN curl -sL https://github.com/rust-lang/rust-analyzer/releases/latest/download/rust-analyzer-$ARCH.gz | gunzip -c - > $RUST_BIN/rust-analyzer; \
    chmod +x $RUST_BIN/rust-analyzer

ENV RUST_PKG=/opt/arm64.dev.rs.22.04.tar.gz
RUN /bin/bash -c "find {$RUSTUP_HOME,$CARGO_HOME} > /tmp/rustlist"
RUN cat /tmp/rustlist | xargs file|grep -v 'directory'|sed -e 's/:/ /g'|awk '{print  $1}' |sort |uniq|tar czf $RUST_PKG -T -

FROM ubuntu:22.04 AS js_install
ENV RUST_PKG=/opt/arm64.dev.rs.22.04.tar.gz
COPY --from=rust_install $RUST_PKG $RUST_PKG
ENV CPP_PKG=/opt/arm64.dev.cpp.22.04.tar.gz
COPY --from=cpp_install $CPP_PKG $CPP_PKG
RUN tar zxf $CPP_PKG -C /

ENV NODEJS_PKG=/opt/arm64.dev.js.22.04.tar.gz
ENV NVM_VERSION=0.39.7
ENV NODE_VERSION=24.2.0
ENV NVM_DIR=/usr/local/nvm
RUN mkdir $NVM_DIR
RUN curl -s -o- https://raw.githubusercontent.com/nvm-sh/nvm/v$NVM_VERSION/install.sh| bash
ENV NODE_PATH=$NVM_DIR/v$NODE_VERSION/lib/node_modules
ENV PATH=$NVM_DIR/versions/node/v$NODE_VERSION/bin:$PATH
RUN npm install -g npm@11.3.0 \
    && npm install yarn gulp-cli -g
RUN npm install --save-dev prettier eslint typescript-language-server unified-language-server typescript -g 

RUN find $NVM_DIR |xargs file|grep -v 'directory'|sed -e 's/:/ /g'|awk '{print  $1}' |sort |uniq|tar czf $NODEJS_PKG -T -

FROM ubuntu:22.04 AS py_install
ENV NODEJS_PKG=/opt/arm64.dev.js.22.04.tar.gz
ENV RUST_PKG=/opt/arm64.dev.rs.22.04.tar.gz
ENV CPP_PKG=/opt/arm64.dev.cpp.22.04.tar.gz
ENV PY_PKG=/opt/arm64.dev.py.22.04.tar.gz
ENV UV_DIR=/root/.local
ENV PATH=$UV_DIR/bin:$PATH
COPY --from=rust_install $RUST_PKG $RUST_PKG
COPY --from=cpp_install $CPP_PKG $CPP_PKG
COPY --from=js_install $NODEJS_PKG $NODEJS_PKG

RUN tar zxf $CPP_PKG -C /
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
RUN uv venv --python 3.12.8
COPY requirements.py312.txt /root/.local/requirements.py312.txt
RUN uv pip install -r /root/.local/requirements.py312.txt
RUN uv pip install setuptools jq matplotlib jupyter notebook ipywidgets jupyterlab-rise jupyter-lsp jupyterlab-lsp jedi-language-server seaborn prettytable
RUN mkdir /root/.jupyter \
    && echo "c.ServerApp.token = ''" > /root/.jupyter/jupyter_notebook_config.py

RUN find $UV_DIR |xargs file|grep -v 'directory'|sed -e 's/:/ /g'|awk '{print  $1}' |sort |uniq|tar czf $PY_PKG -T -

FROM ubuntu:22.04 AS dev
ENV NODEJS_PKG=/opt/arm64.dev.js.22.04.tar.gz
ENV RUST_PKG=/opt/arm64.dev.rs.22.04.tar.gz
ENV CPP_PKG=/opt/arm64.dev.cpp.22.04.tar.gz
ENV PY_PKG=/opt/arm64.dev.py.22.04.tar.gz
COPY --from=rust_install $RUST_PKG $RUST_PKG
COPY --from=cpp_install $CPP_PKG $CPP_PKG
COPY --from=js_install $NODEJS_PKG $NODEJS_PKG
COPY --from=py_install $PY_PKG $PY_PKG

RUN tar zxf $CPP_PKG -C /; \
    tar zxf $RUST_PKG -C /; \
    tar zxf $NODEJS_PKG -C /; \
    tar zxf $PY_PKG -C /; \
