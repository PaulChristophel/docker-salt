FROM photon:5.0 AS base
LABEL maintainer="Paul Christophel <https://github.com/PaulChristophel>" \
      org.opencontainers.image.source="https://github.com/PaulChristophel/docker-salt" \
      org.opencontainers.image.description="Lightweight container image providing a Salt master service."

ARG USER_ID=1000

RUN tdnf -y update \
    && tdnf -y install \
       ca-certificates \
       zeromq \
       postgresql17-libs \
       openldap \
       openssl \
       libgcrypt \
       cryptsetup \
       pcre2 \
       binutils \
       libffi \
       gnupg \
       libssh2 \
       krb5 \
       openssh-clients \
       rsync \
       tini \
       python3 \
       python3-pip \
	   python3-devel \
       shadow \
     && groupadd -g ${USER_ID} salt \
     && useradd -u ${USER_ID} -g salt -d /opt/salt -s /sbin/nologin -m salt \
     && tdnf remove -y shadow \
     && tdnf clean all

FROM base AS builder
LABEL maintainer="Paul Christophel <https://github.com/PaulChristophel>" \
      org.opencontainers.image.source="https://github.com/PaulChristophel/docker-salt" \
      org.opencontainers.image.description="Lightweight container image providing a Salt master service."

ARG REQUIREMENTS=requirements-3006-isalt.txt
ARG USER_ID=1000
ARG FLAGS

ENV PYTHONUNBUFFERED=1 \
    PATH="/usr/local/salt/bin:${PATH}" \
    GENERATE_SALT_SYSPATHS=1 \
    VIRTUAL_ENV=/usr/local/salt

RUN tdnf -y install \
      build-essential \
      gcc \
      glibc-devel \
      zeromq-devel \
      postgresql17-devel \
      openldap-devel \
      openssl-devel \
      cyrus-sasl-devel \
      libffi-devel \
      libssh2-devel \
      krb5-devel \
      pkg-config \
      curl \
      git \
      rust \
      go \
      patch \
    && tdnf clean all

RUN python3 -m venv /usr/local/salt
RUN /usr/local/salt/bin/pip install --no-cache-dir --upgrade wheel
COPY prerequisites.txt /prerequisites.txt
RUN /usr/local/salt/bin/pip install --no-cache-dir -r /prerequisites.txt
COPY ${REQUIREMENTS} /requirements.txt
RUN /usr/local/salt/bin/pip install --no-cache-dir ${FLAGS} -r /requirements.txt
COPY nacl.py /usr/local/salt/lib/python3.11/site-packages/salt/utils/
COPY logstash_engine.py /usr/local/salt/lib/python3.11/site-packages/salt/engines/
COPY app.py /usr/local/salt/lib/python3.11/site-packages/salt/netapi/rest_cherrypy/
RUN find /usr/local/salt -name '*.pyc' -delete && \
    rm -f /usr/local/salt/lib/python3.11/site-packages/salt/returners/django_return.py
RUN find "$VIRTUAL_ENV" -type d -name __pycache__ -exec chown -v ${USER_ID}:${USER_ID} {} \;


FROM golang:trixie AS yescrypt-builder
WORKDIR /build
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates && rm -rf /var/lib/apt/lists/*
COPY ./yescrypt-cli ./
RUN go mod download && CGO_ENABLED=0 go build -trimpath -ldflags="-w -s" -o yescrypt-cli .

FROM base AS salt
LABEL maintainer="Paul Christophel <https://github.com/PaulChristophel>" \
      org.opencontainers.image.source="https://github.com/PaulChristophel/docker-salt" \
      org.opencontainers.image.description="Lightweight container image providing a Salt master service."

ARG USER_ID=1000
COPY --from=builder /usr/local/salt /usr/local/salt
COPY --from=yescrypt-builder /build/yescrypt-cli /usr/local/bin/yescrypt-cli
RUN mkdir -p /srv /var/run/salt /etc/salt/pki/master /etc/salt/pki/minion /etc/salt/master.d /var/log/salt /var/cache/salt/master && \
    chown -R ${USER_ID}:${USER_ID} /srv /etc/salt /var/log/salt /var/cache/salt /var/run/salt && \
    ln -sf /usr/pgsql/17/lib/postgresql/libpq.so.5 /usr/lib64/libpq.so || true && \
    ln -sv /usr/bin/tini /sbin/tini

WORKDIR /opt/salt
USER ${USER_ID}:${USER_ID}

ENV PYTHONUNBUFFERED=1 \
    PATH="/usr/local/salt/bin:${PATH}" \
    MIMIC_SALT_INSTALL=1 \
    VIRTUAL_ENV=/usr/local/salt

ENTRYPOINT ["tini","--","salt-master"]
CMD ["-l","info"]