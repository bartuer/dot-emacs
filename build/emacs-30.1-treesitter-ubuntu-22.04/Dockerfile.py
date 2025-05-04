FROM ubuntu:22.04

WORKDIR /opt
RUN curl -O https://repo.anaconda.com/miniconda/Miniconda3-py38_23.9.0-0-Linux-x86_64.sh
RUN bash Miniconda3-py38_23.9.0-0-Linux-x86_64.sh # non-interactive way
WORKDIR /opt/miniconda/lib/python3.8/site-packages
RUN --mount=type=secret,id=git,dst=/root/.netrc \
    pip install -e "git+https://dev.azure.com/TScience/LLM/_git/LaserTag@31eec88cd23f2fd42bf5c059e83d9834f197df27#egg=lasertag&subdirectory=src/lasertag"
COPY 0001-forms-ai-augloop-protocol.patch src/lasertag
COPY 0002-doc-uuid.patch src/lasertag
COPY 0003-llm-number-and-intent-type.patch src/lasertag
COPY 0004-support-prompt-engineering.patch src/lasertag
COPY 0005-exception-handle.patch src/lasertag
COPY 0006-temperature.patch src/lasertag
COPY 0007-dynamic-prompt.patch src/lasertag
COPY 0008-add-templatenames.patch src/lasertag
COPY 0009-add-formId.patch src/lasertag
COPY 0010-model-from-schema.patch src/lasertag
COPY 0011-operation-as-property-and-method.patch src/lasertag
COPY 0012-schema-message-types.patch src/lasertag
COPY 0013-add-patch-command.patch src/lasertag
COPY 0014-business-goal-schema.patch src/lasertag
RUN cd src/lasertag \
    && git config --global user.email "bazhou@microsoft.com" \
    && git config --global user.name "Bartuer Zhou" \
    && git am 0001-forms-ai-augloop-protocol.patch \
    && git am 0002-doc-uuid.patch \
    && git am 0003-llm-number-and-intent-type.patch \
    && git am 0004-support-prompt-engineering.patch \
    && git am 0005-exception-handle.patch \
    && git am 0006-temperature.patch \
    && git am 0007-dynamic-prompt.patch \
    && git am 0008-add-templatenames.patch \
    && git am 0009-add-formId.patch \
    && git am 0010-model-from-schema.patch \
    && git am 0011-operation-as-property-and-method.patch \
    && git am 0012-schema-message-types.patch \
    && git am 0013-add-patch-command.patch \
    && git am 0014-business-goal-schema.patch \
    && cd /opt/miniconda/lib/python3.8/site-packages

# rsync -ave ssh alcli:/opt/miniconda/lib/python3.8/site-packages/src/ ./src/
COPY requirements.txt /opt/
RUN pip install -r /opt/requirements.txt
COPY demjson.py /opt/miniconda/lib/python3.8/site-packages/demjson.py
COPY requirements.txt /opt/miniconda/lib/python3.8/site-packages/src/lasertag/requirements.txt

RUN pip install setuptools jq matplotlib jupyter notebook ipywidgets jupyterlab-rise jupyter-lsp jupyterlab-lsp jedi-language-server seaborn prettytable \
    && mkdir /root/.jupyter \
    && echo "c.ServerApp.token = ''" > /root/.jupyter/jupyter_notebook_config.py

RUN pip install az-cli
RUN git config --global --add safe.directory /root/etc/el

