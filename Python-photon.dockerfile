ARG PHOTON_RELEASE=5.0
ARG BASE_IMAGE=photon:${PHOTON_RELEASE}
FROM ${BASE_IMAGE} AS base
ARG PHOTON_RELEASE
# Share the interpreter packages between the build and runtime roots.
RUN tdnf -y install python3 python3-pip python3-devel findutils \
 && tdnf clean all

FROM base AS builder

ARG REQUIREMENTS_DIRECTORY=requirements
ARG COMMON_REQUIREMENTS=common.txt
ARG PYTHON_REQUIREMENTS=python/3.11.txt
ARG PROFILE_REQUIREMENTS=profiles/standard.txt
ARG SALT_REQUIREMENT=salt==3008.2
ARG USER_ID=1000
ARG FLAGS
ARG PYTHONPATH="/usr/local/salt/lib/python3.11"

ENV PYTHONUNBUFFERED=1 \
    PATH="/usr/local/salt/bin:${PATH}" \
    GENERATE_SALT_SYSPATHS=1 \
    VIRTUAL_ENV=/usr/local/salt

RUN sed -i 's/^enabled=0/enabled=1/' /etc/yum.repos.d/photon.repo \
 && sed -i 's/^enabled=0/enabled=1/' /etc/yum.repos.d/photon-release.repo || true \
 && tdnf clean all \
 && rm -rf /var/cache/tdnf \
 && tdnf makecache \
 && tdnf -y --exclude=python3,python3-libs install \
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

# tdnf resolves the runtime dependency closure and records it in the RPM DB.
FROM base AS runtime-root
ARG PHOTON_RELEASE
ARG USER_ID=1000
RUN tdnf -y install shadow rpm \
 && python_package="$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}' python3)" \
 && python_libs_package="$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}' python3-libs)" \
 && mkdir -p /mnt/rootfs \
 && tdnf -i /mnt/rootfs --releasever=${PHOTON_RELEASE} install -y \
      filesystem glibc libselinux coreutils findutils \
 && tdnf -i /mnt/rootfs --releasever=${PHOTON_RELEASE} install -y \
      photon-release ca-certificates tzdata bash sed \
      zeromq postgresql17-libs openldap openssl libgcrypt cryptsetup \
      pcre2 libffi gnupg libssh2 krb5 openssh-clients rsync tini \
      "$python_package" \
      "$python_libs_package" \
 && tdnf -i /mnt/rootfs --releasever=${PHOTON_RELEASE} clean all \
 && rm -rf /mnt/rootfs/var/cache/tdnf /mnt/rootfs/var/lib/tdnf/cache /mnt/rootfs/usr/share/man /mnt/rootfs/usr/share/doc \
 && groupadd --root /mnt/rootfs -g ${USER_ID} salt \
 && useradd --root /mnt/rootfs -u ${USER_ID} -g salt -d /opt/salt -s /bin/false -m salt \
 && mkdir -p /mnt/rootfs/srv /mnt/rootfs/run/salt \
      /mnt/rootfs/etc/salt/pki/master /mnt/rootfs/etc/salt/pki/minion \
      /mnt/rootfs/etc/salt/master.d /mnt/rootfs/var/log/salt /mnt/rootfs/var/cache/salt/master \
 && chown -R ${USER_ID}:${USER_ID} /mnt/rootfs/srv /mnt/rootfs/etc/salt \
      /mnt/rootfs/var/log/salt /mnt/rootfs/var/cache/salt /mnt/rootfs/run/salt \
 && libpq="$(find /mnt/rootfs/usr -name libpq.so.5 -print -quit)" \
 && test -n "$libpq" \
 && ln -sf "${libpq#/mnt/rootfs}" /mnt/rootfs/usr/lib64/libpq.so \
 && chmod 1777 /mnt/rootfs/tmp

FROM runtime-root AS runtime-builder
COPY --from=builder /usr/local/salt/ /mnt/rootfs/usr/local/salt/
RUN find /mnt/rootfs/usr/local/salt -name '*.pyc' -delete

# Fail the build if the assembled root cannot run its interpreter or entrypoint.
RUN chroot /mnt/rootfs /usr/bin/tini --version \
 && PYTHONDONTWRITEBYTECODE=1 chroot /mnt/rootfs /usr/local/salt/bin/salt-master --version \
 && test -s /mnt/rootfs/etc/os-release \
 && test -s /mnt/rootfs/etc/pki/tls/certs/ca-bundle.crt

FROM scratch AS salt
ARG PHOTON_RELEASE
LABEL maintainer="Paul Christophel <https://github.com/PaulChristophel>" \
      org.opencontainers.image.authors="Paul Christophel" \
      org.opencontainers.image.title="Salt Master" \
      org.opencontainers.image.source="https://github.com/PaulChristophel/docker-salt" \
      org.opencontainers.image.url="https://github.com/PaulChristophel/docker-salt" \
      org.opencontainers.image.documentation="https://github.com/PaulChristophel/docker-salt#readme" \
      org.opencontainers.image.description="Lightweight container image providing a Salt master service." \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.base.name="docker.io/library/photon:${PHOTON_RELEASE}"

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
