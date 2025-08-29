FROM ubuntu:22.04 AS cpp_install

RUN export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y apt-transport-https autoconf bash-completion bsdmainutils
RUN export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y build-essential gdb libtool clang llvm lldb clang-tools clangd clang-format
RUN export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y netcat ninja-build iputils-ping software-properties-common tar texinfo unzip valgrind xclip zip zlib1g-dev  ca-certificates  parallel file pkg-config libssl-dev cmake curl file gnupg-agent libblas-dev libgraphviz-dev jq htop linux-tools-common linux-tools-generic uuid-dev libzmq3-dev iproute2

ENV CPP_PKG=/opt/arm64.dev.cc.22.04.tar.gz
RUN apt list --installed|awk -F"/" '{print $1}'|parallel dpkg -L :::|sort|uniq|xargs file|grep -v "directory"|sed -e 's/:/ /g'|awk '{print $2, " ", $1}' |sort |uniq|grep -v "^SVG " |grep -v "^PNG " |grep -v "^PDF" |grep -v "^broken" |grep -v "cannot"|grep -v "^directory" |grep -iv "copyright"|grep -v "changelog.Debian.gz" |awk '{print $2}' |sed '$a /etc/ssl/certs'|sed '$a /etc/alternatives'|sed '$a /usr/bin'|sort |uniq|tar czf $CPP_PKG -T -

FROM ubuntu:22.04 AS rust_install

ENV CPP_PKG=/opt/arm64.dev.cc.22.04.tar.gz
COPY --from=cpp_install $CPP_PKG $CPP_PKG

ENV RUSTUP_HOME=/root/.rustup \
    CARGO_HOME=/root/.cargo \
    RUST_BIN=/root/.cargo/bin \
    PATH=/root/.cargo/bin:$PATH \
    ARCH=aarch64-unknown-linux-gnu \
    RUST_VERSION=1.87.0

RUN tar zxf $CPP_PKG -C /

RUN curl -k  -sSf https://sh.rustup.rs | sh -s -- -y
RUN cargo install --no-default-features wasm-pack cargo-generate wasm-bindgen-cli evcxr_jupyter

RUN rustup component add rust-analyzer rust-src

ENV RUST_PKG=/opt/arm64.dev.rs.22.04.tar.gz
RUN /bin/bash -c "find {$RUSTUP_HOME,$CARGO_HOME} > /tmp/rustlist"
RUN cat /tmp/rustlist | xargs file|grep -v 'directory'|sed -e 's/:/ /g'|awk '{print  $1}' |sort |uniq|tar czf $RUST_PKG -T -

FROM ubuntu:22.04 AS js_install
ENV RUST_PKG=/opt/arm64.dev.rs.22.04.tar.gz
COPY --from=rust_install $RUST_PKG $RUST_PKG
ENV CPP_PKG=/opt/arm64.dev.cc.22.04.tar.gz
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
RUN npm install --omit=dev --omit=optional prettier eslint typescript-language-server unified-language-server typescript  vscode-json-languageserver-bin vscode-html-languageserver-bin vscode-css-languageserver-bin tslab -g 

RUN find $NVM_DIR |xargs file|grep -v 'directory'|sed -e 's/:/ /g'|awk '{print  $1}' |sort |uniq|tar czf $NODEJS_PKG -T -

FROM ubuntu:22.04 AS py_install
ENV NODEJS_PKG=/opt/arm64.dev.js.22.04.tar.gz
ENV RUST_PKG=/opt/arm64.dev.rs.22.04.tar.gz
ENV CPP_PKG=/opt/arm64.dev.cc.22.04.tar.gz
ENV NODEJS_PKG=/opt/arm64.dev.js.22.04.tar.gz
ENV RUSTUP_HOME=/root/.rustup
ENV CARGO_HOME=/root/.cargo
ENV RUST_BIN=/root/.cargo/bin
ENV ARCH=aarch64-unknown-linux-gnu
ENV RUST_VERSION=1.87.0

ENV PY_PKG=/opt/arm64.dev.py.22.04.tar.gz
ENV UV_DIR=/root/.local
ENV PATH=$UV_DIR/bin:$PATH
COPY --from=rust_install $RUST_PKG $RUST_PKG
COPY --from=cpp_install $CPP_PKG $CPP_PKG
COPY --from=js_install $NODEJS_PKG $NODEJS_PKG

RUN tar zxf $CPP_PKG -C /
RUN tar zxf $NODEJS_PKG -C /
RUN tar zxf $RUST_PKG -C /
ENV NVM_VERSION=0.39.7
ENV NODE_VERSION=24.2.0
ENV NVM_DIR=/usr/local/nvm

RUN curl -LsSf https://astral.sh/uv/install.sh | sh
WORKDIR $UV_DIR
RUN uv venv --python 3.12.8
COPY requirements.py312.txt /root/.local/requirements.py312.txt
RUN uv pip install --no-cache-dir -r /root/.local/requirements.py312.txt
RUN uv pip install --no-cache-dir setuptools jq matplotlib jupyter notebook ipywidgets jupyterlab-rise jupyter-lsp jupyterlab-lsp jedi-language-server seaborn prettytable bash_kernel aider-install 
RUN mkdir /root/.jupyter \
    && echo "c.ServerApp.token = ''" > /root/.jupyter/jupyter_notebook_config.py
SHELL ["/bin/bash", "-c"]
ENV PATH=$UV_DIR/bin:$NVM_DIR/versions/node/v$NODE_VERSION/bin:$RUST_BIN:$PATH
ENV JUPYTER_PATH=$UV_DIR/.venv/share/jupyter/
RUN source $UV_DIR/.venv/bin/activate; \
    tslab install --prefix $UV_DIR/.venv; \
    evcxr_jupyter --install; \
    jupyter kernelspec list
RUN aider-install
COPY rust-analyzer.json $UV_DIR/.venv/etc/jupyter/jupyter_server_config.d/rust-analyzer.json
COPY clangd.json $UV_DIR/.venv/etc/jupyter/jupyter_server_config.d/clangd.json
RUN cat <(find $UV_DIR |xargs file|grep -v 'directory'|sed -e 's/:/ /g'|awk '{print  $1}') <(find /root/.jupyter)|sort |uniq|tar czf $PY_PKG -T -

FROM ubuntu:22.04 AS dev
ENV NODEJS_PKG=/opt/arm64.dev.js.22.04.tar.gz
ENV RUST_PKG=/opt/arm64.dev.rs.22.04.tar.gz
ENV CPP_PKG=/opt/arm64.dev.cc.22.04.tar.gz
ENV PY_PKG=/opt/arm64.dev.py.22.04.tar.gz
ENV DEV_PKG=/opt/arm64.dev.base.22.04.tar.gz
COPY --from=rust_install $RUST_PKG $RUST_PKG
COPY --from=cpp_install $CPP_PKG $CPP_PKG
COPY --from=js_install $NODEJS_PKG $NODEJS_PKG
COPY --from=py_install $PY_PKG $PY_PKG

RUN apt-get update && DEBIAN_FRONTEND=noninteractive \
        && apt-get install -y --no-install-recommends \
        git openssh-client openssh-server parallel file

ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
RUN git config --global --add safe.directory /root/etc/el
RUN git config --global user.name "Bartuer Zhou"
RUN git config --global user.email "bartuer@gmail.com"
RUN git config --global core.pager cat
RUN git config --global http.proxy 'socks5://host.docker.internal:8080'

COPY entry.sh /bin/entry
RUN mkdir -p /root/.ssh
COPY config /root/.ssh/config
COPY authorized_keys /root/.ssh/authorized_keys
COPY .bashrc /root/.bashrc
RUN mkdir -p /root/local/bin
COPY install.arm64.sh /root/local/bin/install.arm64.sh

SHELL ["/bin/bash", "-c"]

RUN cat <(apt list --installed|grep -E "ssh|libwrap0"|awk -F"/" '{print $1}'|parallel dpkg -L :::|sort|uniq|grep -v man1|grep -v man5|grep -v man8|grep -v "usr/share/doc"|xargs file|grep -v "directory"|sed -e 's/:/ /g'|awk '{print $2, " ", $1}' |sort |uniq|awk '{print $2}'  | sed '$a /etc/passwd' | sed '$a /root/.ssh/config' | sed '$a /root/.ssh/authorized_keys' | sed '$a /bin/entry' )  <(apt list --installed|grep git|awk -F"/" '{print $1}'|parallel dpkg -L :::|sort|uniq|grep -v "usr/share/doc"|xargs file|grep -v "directory"|sed -e 's/:/ /g'|awk '{print $2, " ", $1}' |sort |uniq|awk '{print $2}'|sed '$a /root/.gitconfig'|sed '$a /root/local/bin/install.arm64.sh' |sed '$a /etc/timezone' |sed '$a /root/.bashrc') <(find /etc/ssh) |tar czf $DEV_PKG -T -

EXPOSE 22
ENTRYPOINT ["/bin/entry"]