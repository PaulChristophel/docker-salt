ARG PYTHON_RELEASE=3.11-slim
FROM python:${PYTHON_RELEASE} AS base
LABEL maintainer="Paul Christophel <https://github.com/PaulChristophel>" \
      org.opencontainers.image.source="https://github.com/PaulChristophel/docker-salt" \
      org.opencontainers.image.description="Lightweight container image providing a Salt master service."

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      libzmq5 \
      libpq5 \
      libldap-2* \
      libssl3 \
      openssl \
      libgcrypt20 \
      cryptsetup-bin \
      libpcre2-8-0 \
      binutils \
      libffi8 \
      gnupg \
      libgit2-1.* \
      libssh2-1 \
      krb5-user \
      libkrb5-3 \
      openssh-client \
      rsync \
      tini \
    && rm -rf /var/lib/apt/lists/*

FROM base AS builder
LABEL maintainer="Paul Christophel <https://github.com/PaulChristophel>" \
      org.opencontainers.image.source="https://github.com/PaulChristophel/docker-salt" \
      org.opencontainers.image.description="Lightweight container image providing a Salt master service."

ARG REQUIREMENTS_DIRECTORY=requirements
ARG COMMON_REQUIREMENTS=common.txt
ARG PYTHON_REQUIREMENTS=python/3.11.txt
ARG PROFILE_REQUIREMENTS=profiles/standard.txt
ARG SALT_REQUIREMENT=salt==3008.2
ARG FLAGS
ARG USER_ID=1000
ARG PYTHONPATH="/usr/local/salt/lib/python3.11"

ENV PYTHONUNBUFFERED=1 \
    PATH="/usr/local/salt/bin:${PATH}" \
    GENERATE_SALT_SYSPATHS=1 \
    VIRTUAL_ENV=/usr/local/salt

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      gcc \
      libc6-dev \
      linux-headers-amd64 \
      libzmq3-dev \
      libpq-dev \
      libldap2-dev \
      libssl-dev \
      libsasl2-dev \
      libffi-dev \
      libgit2-dev \
      libssh2-1-dev \
      krb5-multidev \
      pkg-config \
      curl \
      git \
      rustc \
      cargo \
      python3-dev \
      postgresql-server-dev-all \
      patch \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /usr/local/salt
RUN /usr/local/salt/bin/pip install --no-cache-dir --upgrade pip wheel setuptools
COPY prerequisites.txt /prerequisites.txt
RUN /usr/local/salt/bin/pip install --no-cache-dir -r /prerequisites.txt
COPY ${REQUIREMENTS_DIRECTORY}/ /requirements/
RUN /usr/local/salt/bin/pip install --no-cache-dir ${FLAGS} \
      -r "/requirements/${COMMON_REQUIREMENTS}" \
      -r "/requirements/${PYTHON_REQUIREMENTS}" \
      -r "/requirements/${PROFILE_REQUIREMENTS}" \
      "${SALT_REQUIREMENT}"
COPY nacl.py "${PYTHONPATH}/site-packages/salt/utils/"
COPY logstash_engine.py "${PYTHONPATH}/site-packages/salt/engines/"
COPY app.py "${PYTHONPATH}/site-packages/salt/netapi/rest_cherrypy/"
RUN find /usr/local/salt -name '*.pyc' -delete && \
    rm -f "${PYTHONPATH}/site-packages/salt/returners/django_return.py"
RUN find "$VIRTUAL_ENV" -type d -name __pycache__ -exec chown -v ${USER_ID}:${USER_ID} {} \;

FROM base AS salt
LABEL maintainer="Paul Christophel <https://github.com/PaulChristophel>" \
      org.opencontainers.image.source="https://github.com/PaulChristophel/docker-salt" \
      org.opencontainers.image.description="Lightweight container image providing a Salt master service."

ARG USER_ID=1000
COPY --from=builder /usr/local/salt /usr/local/salt
RUN groupadd -g ${USER_ID} salt && \
    useradd -u ${USER_ID} -g ${USER_ID} -s /usr/sbin/nologin -d /opt/salt -m salt
RUN mkdir -p /srv /var/run/salt /etc/salt/pki/master /etc/salt/pki/minion /etc/salt/master.d /var/log/salt /var/cache/salt/master && \
    chown -R ${USER_ID}:${USER_ID} /srv /etc/salt /var/log/salt /var/cache/salt /var/run/salt && \
    ln -sf /usr/lib/x86_64-linux-gnu/libpq.so.5 /usr/lib/x86_64-linux-gnu/libpq.so && \
    ln -sv /usr/bin/tini-static /sbin/tini

WORKDIR /opt/salt
USER ${USER_ID}:${USER_ID}

ENV PYTHONUNBUFFERED=1 \
    PATH="/usr/local/salt/bin:${PATH}" \
    MIMIC_SALT_INSTALL=1 \
    VIRTUAL_ENV=/usr/local/salt

ENTRYPOINT ["tini","--","salt-master"]
CMD ["-l","info"]
