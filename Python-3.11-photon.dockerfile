FROM photon:5.0 AS python-base

# ensure local python is preferred over distribution python
ENV PATH=/usr/local/bin:$PATH
ENV LANG=C.UTF-8

# runtime and build dependencies
RUN set -eux; \
	tdnf update -y; \
	tdnf install -y \
		build-essential \
		wget \
		gnupg \
		ca-certificates \
		xz \
		zlib-devel \
		bzip2-devel \
		openssl-devel \
		libffi-devel \
		sqlite-devel \
		readline-devel \
		findutils \
		gdb \
	; \
	tdnf clean all; \
	rm -rf /var/cache/tdnf

ENV GPG_KEY=A035C8C19219BA821ECEA86B64E628F8D684696D
ENV PYTHON_VERSION=3.11.14
ENV PYTHON_SHA256=8d3ed8ec5c88c1c95f5e558612a725450d2452813ddad5e58fdb1a53b1209b78

RUN set -eux; \
	\
	wget -O python.tar.xz "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz"; \
	echo "$PYTHON_SHA256 *python.tar.xz" | sha256sum -c -; \
	wget -O python.tar.xz.asc "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz.asc"; \
	GNUPGHOME="$(mktemp -d)"; export GNUPGHOME; \
	gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys "$GPG_KEY"; \
	gpg --batch --verify python.tar.xz.asc python.tar.xz; \
	gpgconf --kill all; \
	rm -rf "$GNUPGHOME" python.tar.xz.asc; \
	mkdir -p /usr/src/python; \
	tar --extract --directory /usr/src/python --strip-components=1 --file python.tar.xz; \
	rm python.tar.xz; \
	\
	cd /usr/src/python; \
	arch="$(uname -m)"; \
	lto_flag="--with-lto"; \
	if [ "$arch" = "riscv64" ]; then lto_flag=""; fi; \
	./configure \
		--enable-loadable-sqlite-extensions \
		--enable-optimizations \
		--enable-option-checking=fatal \
		--enable-shared \
		"$lto_flag" \
		--with-ensurepip \
	; \
	nproc="$(getconf _NPROCESSORS_ONLN || nproc)"; \
	make -j "$nproc"; \
	\
	# prevent accidental usage of a system installed libpython of the same version
	rm python; \
	make -j "$nproc" \
		"LDFLAGS=${LDFLAGS:--Wl,-rpath='\$\$ORIGIN/../lib'}" \
		python \
	; \
	make install; \
	\
	# enable GDB to load debugging data
	bin="$(readlink -ve /usr/local/bin/python3)"; \
	dir="$(dirname "$bin")"; \
	mkdir -p "/usr/share/gdb/auto-load/$dir"; \
	cp -vL Tools/gdb/libpython.py "/usr/share/gdb/auto-load/$bin-gdb.py"; \
	\
	cd /; \
	rm -rf /usr/src/python; \
	\
	find /usr/local -depth \
		\( \
			\( -type d -a \( -name test -o -name tests -o -name idle_test \) \) \
			-o \( -type f -a \( -name '*.pyc' -o -name '*.pyo' -o -name 'libpython*.a' \) \) \
		\) -exec rm -rf '{}' + \
	; \
	\
	ldconfig; \
	\
	export PYTHONDONTWRITEBYTECODE=1; \
	python3 --version; \
	\
	pip3 install \
		--disable-pip-version-check \
		--no-cache-dir \
		--no-compile \
		'setuptools==79.0.1' \
		'wheel<0.46' \
	; \
	pip3 --version

# make some useful symlinks that are expected to exist ("/usr/local/bin/python" and friends)
RUN set -eux; \
	for src in idle3 pip3 pydoc3 python3 python3-config; do \
		dst="$(echo "$src" | tr -d 3)"; \
		[ -s "/usr/local/bin/$src" ]; \
		[ ! -e "/usr/local/bin/$dst" ]; \
		ln -svT "$src" "/usr/local/bin/$dst"; \
	done

CMD ["python3"]

FROM python-base AS base
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