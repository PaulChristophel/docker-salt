ARG PYTHON_RELEASE=3.11-slim
ARG BASE_IMAGE=python:${PYTHON_RELEASE}
FROM ${BASE_IMAGE} AS base
ARG PYTHON_RELEASE
ENV DEBIAN_FRONTEND=noninteractive

FROM base AS builder

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

# Bootstrap the same Debian release as the CPython base into an empty root.
# Keep dpkg metadata and OS identity; no build packages enter this filesystem.
# Build containers cannot mount /dev, /proc or /sys inside the new root.
FROM base AS runtime-root
ARG USER_ID=1000
RUN apt-get update && apt-get install -y --no-install-recommends mmdebstrap \
 && . /etc/os-release \
 && mmdebstrap --mode=root --variant=minbase --skip=chroot/mount \
      "$VERSION_CODENAME" /mnt/rootfs https://deb.debian.org/debian \
 && rm -f /mnt/rootfs/etc/apt/sources.list \
 && cp -a /etc/apt/sources.list.d/. /mnt/rootfs/etc/apt/sources.list.d/ \
 && if [ -f /etc/apt/sources.list ]; then cp /etc/apt/sources.list /mnt/rootfs/etc/apt/sources.list; fi \
 && cp /etc/resolv.conf /mnt/rootfs/etc/resolv.conf \
 && chroot /mnt/rootfs apt-get update \
 && chroot /mnt/rootfs apt-get upgrade -y \
 && chroot /mnt/rootfs apt-get install -y --no-install-recommends \
      ca-certificates tzdata bash coreutils findutils sed \
      openssl libffi8 zlib1g libbz2-1.0 liblzma5 libreadline8 \
      libsqlite3-0 libgdbm6 libgdbm-compat4 libncursesw6 libuuid1 \
      libexpat1 libzstd1 libcrypt1 \
      libzmq5 libpq5 libgcrypt20 cryptsetup-bin libpcre2-8-0 \
      gnupg libssh2-1 krb5-user libkrb5-3 openssh-client rsync tini \
 && chroot /mnt/rootfs apt-get install -y --no-install-recommends \
      '?and(?name(^libldap[-0-9]),?not(?name(dev)),?not(?name(dbg)))' \
      '?and(?name(^libgit2-[0-9]),?not(?name(dev)),?not(?name(dbg)))' \
 && chroot /mnt/rootfs apt-get clean \
 && rm -rf /mnt/rootfs/var/lib/apt/lists/* /mnt/rootfs/var/cache/apt/* \
      /mnt/rootfs/usr/share/man /mnt/rootfs/usr/share/doc \
 && groupadd --root /mnt/rootfs -g ${USER_ID} salt \
 && useradd --root /mnt/rootfs -u ${USER_ID} -g salt -s /usr/sbin/nologin -d /opt/salt -m salt \
 && mkdir -p /mnt/rootfs/srv /mnt/rootfs/run/salt \
      /mnt/rootfs/etc/salt/pki/master /mnt/rootfs/etc/salt/pki/minion \
      /mnt/rootfs/etc/salt/master.d /mnt/rootfs/var/log/salt /mnt/rootfs/var/cache/salt/master \
 && chown -R ${USER_ID}:${USER_ID} /mnt/rootfs/srv /mnt/rootfs/etc/salt \
      /mnt/rootfs/var/log/salt /mnt/rootfs/var/cache/salt /mnt/rootfs/run/salt \
 && libpq="$(find /mnt/rootfs/usr/lib -name libpq.so.5 -print -quit)" \
 && test -n "$libpq" \
 && ln -s libpq.so.5 "${libpq%.5}" \
 && chmod 1777 /mnt/rootfs/tmp

FROM runtime-root AS runtime-builder
# CPython is source-built in the upstream image, so copy its runtime separately.
COPY --from=base /usr/local/ /mnt/rootfs/usr/local/
COPY --from=builder /usr/local/salt/ /mnt/rootfs/usr/local/salt/
RUN rm -rf /mnt/rootfs/usr/local/include /mnt/rootfs/usr/local/share/man \
      /mnt/rootfs/usr/local/lib/pkgconfig /mnt/rootfs/usr/local/lib/python*/test \
 && find /mnt/rootfs/usr/local -name '*.pyc' -delete \
 && chroot /mnt/rootfs /sbin/ldconfig

# Check Tini and static metadata; Salt startup needs a container-mounted /proc.
RUN chroot /mnt/rootfs /usr/bin/tini --version \
 && test -s /mnt/rootfs/etc/os-release \
 && test -s /mnt/rootfs/etc/ssl/certs/ca-certificates.crt

FROM scratch AS salt
ARG PYTHON_RELEASE
LABEL maintainer="Paul Christophel <https://github.com/PaulChristophel>" \
      org.opencontainers.image.authors="Paul Christophel" \
      org.opencontainers.image.title="Salt Master" \
      org.opencontainers.image.source="https://github.com/PaulChristophel/docker-salt" \
      org.opencontainers.image.url="https://github.com/PaulChristophel/docker-salt" \
      org.opencontainers.image.documentation="https://github.com/PaulChristophel/docker-salt#readme" \
      org.opencontainers.image.description="Lightweight container image providing a Salt master service." \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.base.name="docker.io/library/python:${PYTHON_RELEASE}"

ARG USER_ID=1000
COPY --from=runtime-builder /mnt/rootfs/ /

WORKDIR /opt/salt
USER ${USER_ID}:${USER_ID}

ENV PYTHONUNBUFFERED=1 \
    PATH="/usr/local/salt/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    LANG=C.UTF-8 \
    MIMIC_SALT_INSTALL=1 \
    VIRTUAL_ENV=/usr/local/salt

ENTRYPOINT ["tini","--","salt-master"]
CMD ["-l","info"]
