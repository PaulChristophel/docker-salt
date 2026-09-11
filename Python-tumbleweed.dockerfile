ARG PYTHON_RELEASE=3.14-tumbleweed
ARG BASE_IMAGE=docker.io/pcm0/python:${PYTHON_RELEASE}
FROM ${BASE_IMAGE} AS base
FROM base AS builder

ARG REQUIREMENTS_DIRECTORY=requirements
ARG COMMON_REQUIREMENTS=common.txt
ARG PYTHON_REQUIREMENTS=python/3.14.txt
ARG PROFILE_REQUIREMENTS=profiles/standard.txt
ARG SALT_REQUIREMENT=salt==3008.2
ARG USER_ID=1000
ARG FLAGS
ARG PYTHONPATH="/usr/local/salt/lib/python3.14"

ENV PYTHONUNBUFFERED=1 \
    PATH="/usr/local/salt/bin:${PATH}" \
    GENERATE_SALT_SYSPATHS=1 \
    VIRTUAL_ENV=/usr/local/salt

# CPython and its headers are supplied by the Python base image.
RUN zypper --non-interactive --gpg-auto-import-keys install --no-recommends \
      findutils \
      gcc \
      gcc-c++ \
      make \
      glibc-devel \
      linux-glibc-devel \
      zeromq-devel \
      postgresql-devel \
      postgresql-server-devel \
      openldap2-devel \
      libopenssl-devel \
      cyrus-sasl-devel \
      libffi-devel \
      libgit2-devel \
      libssh2-devel \
      krb5-devel \
      libxcrypt-devel \
      pkg-config \
      curl \
      git \
      rust \
      cargo \
      go \
      patch \
 && zypper --non-interactive clean --all \
 && rm -rf /var/cache/zypp

RUN /usr/local/bin/python3 -m venv /usr/local/salt
RUN /usr/local/salt/bin/pip install --no-cache-dir --upgrade wheel
COPY prerequisites.txt /prerequisites.txt
RUN /usr/local/salt/bin/pip install --no-cache-dir -r /prerequisites.txt
COPY ${REQUIREMENTS_DIRECTORY}/ /requirements/
# Install our explicit pins without resolving upstream dependency constraints.
# The requirements files must include all required runtime dependencies.
RUN /usr/local/salt/bin/pip install --no-cache-dir ${FLAGS} \
      -r "/requirements/${COMMON_REQUIREMENTS}" \
      -r "/requirements/${PYTHON_REQUIREMENTS}" \
      -r "/requirements/${PROFILE_REQUIREMENTS}"
RUN /usr/local/salt/bin/pip install --no-cache-dir ${FLAGS} "${SALT_REQUIREMENT}"
COPY nacl.py "${PYTHONPATH}/site-packages/salt/utils/"
COPY logstash_engine.py "${PYTHONPATH}/site-packages/salt/engines/"
COPY app.py "${PYTHONPATH}/site-packages/salt/netapi/rest_cherrypy/"
RUN find /usr/local/salt -name '*.pyc' -delete && \
    rm -f "${PYTHONPATH}/site-packages/salt/returners/django_return.py"
RUN find "$VIRTUAL_ENV" -type d -name __pycache__ -exec chown -v ${USER_ID}:${USER_ID} {} \;

# Construct an independent runtime root; zypper and build tools stay outside it.
FROM base AS runtime-builder
ARG USER_ID=1000

ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

RUN zypper --non-interactive --gpg-auto-import-keys install --no-recommends shadow findutils \
 && mkdir -p /mnt/rootfs \
 && zypper --installroot /mnt/rootfs --non-interactive --gpg-auto-import-keys \
      install --no-recommends \
      openSUSE-release \
      util-linux \
      bash \
      coreutils \
      findutils \
      sed \
      openssl \
      ca-certificates \
      ca-certificates-mozilla \
      timezone \
      libopenssl3 \
      libffi8 \
      libz1 \
      libbz2-1 \
      liblzma5 \
      libreadline8 \
      libsqlite3-0 \
      libgdbm6 \
      libgdbm_compat4 \
      libncurses6 \
      libuuid1 \
      libzstd1 \
      libexpat1 \
      libmpdec4 \
      libzmq5 \
      libpq5 \
      libldap2 \
      libcrypt1 \
      gpg2 \
      libgit2-1_9 \
      libssh2-1 \
      krb5 \
      openssh-clients \
      rsync \
      tini \
 && zypper --installroot /mnt/rootfs --non-interactive clean --all \
 && rm -rf /mnt/rootfs/var/cache/zypp /mnt/rootfs/var/log/zypp \
      /mnt/rootfs/usr/share/man /mnt/rootfs/usr/share/doc \
 && groupadd --root /mnt/rootfs -g ${USER_ID} salt \
 && useradd --root /mnt/rootfs -u ${USER_ID} -g salt -d /opt/salt -s /bin/false -m salt \
 && mkdir -p /mnt/rootfs/srv /mnt/rootfs/var/run/salt \
      /mnt/rootfs/etc/salt/pki/master /mnt/rootfs/etc/salt/pki/minion \
      /mnt/rootfs/etc/salt/master.d /mnt/rootfs/var/log/salt /mnt/rootfs/var/cache/salt/master \
 && chown -R ${USER_ID}:${USER_ID} /mnt/rootfs/srv /mnt/rootfs/etc/salt \
      /mnt/rootfs/var/log/salt /mnt/rootfs/var/cache/salt /mnt/rootfs/var/run/salt \
 && ln -sf /usr/lib64/libpq.so.5 /mnt/rootfs/usr/lib64/libpq.so \
 && chmod 1777 /mnt/rootfs/tmp

# Reuse the upstream CPython build, including its shared library and stdlib.
COPY --from=base /usr/local/ /mnt/rootfs/usr/local/
COPY --from=builder /usr/local/salt/ /mnt/rootfs/usr/local/salt/
RUN rm -rf /mnt/rootfs/usr/local/include /mnt/rootfs/usr/local/share/man \
      /mnt/rootfs/usr/local/lib/pkgconfig /mnt/rootfs/usr/local/lib/python*/test \
 && find /mnt/rootfs/usr/local -name '*.pyc' -delete

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
      org.opencontainers.image.base.name="docker.io/pcm0/python:${PYTHON_RELEASE}"

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
