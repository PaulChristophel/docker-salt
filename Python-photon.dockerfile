ARG PHOTON_RELEASE=5.0
FROM photon:${PHOTON_RELEASE} AS base
LABEL maintainer="Paul Christophel <https://github.com/PaulChristophel>" \
      org.opencontainers.image.source="https://github.com/PaulChristophel/docker-salt" \
      org.opencontainers.image.description="Lightweight container image providing a Salt master service."

ARG USER_ID=1000

RUN tdnf -y install \
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

FROM base AS salt
LABEL maintainer="Paul Christophel <https://github.com/PaulChristophel>" \
      org.opencontainers.image.source="https://github.com/PaulChristophel/docker-salt" \
      org.opencontainers.image.description="Lightweight container image providing a Salt master service."

ARG USER_ID=1000
COPY --from=builder /usr/local/salt /usr/local/salt
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
