FROM python:3.11-alpine AS base
MAINTAINER Paul Martin
RUN apk upgrade --update --no-cache && \
    apk add --update --no-cache ca-certificates libzmq libpq libldap libcrypto3 libssl3 openssl libgcrypt cryptsetup pcre2 binutils openssl-dev libffi gnupg libgit2 libssh2 krb5 krb5-libs openssh-client-default openssh-client-common rsync

FROM base as builder
MAINTAINER Paul Martin
ARG REQUIREMENTS=requirements-3006-isalt.txt
ARG FLAGS
ARG USER_ID=1000
ENV PYTHONUNBUFFERED=1 PATH="/usr/local/salt/bin:${PATH}" GENERATE_SALT_SYSPATHS=1 VIRTUAL_ENV=/usr/local/salt

RUN apk add --update --no-cache alpine-sdk musl-dev zeromq-dev libpq-dev openldap-dev gcc libc-dev linux-headers libffi-dev libgit2-dev libssh2-dev rust cargo wget tar git build-base krb5-dev postgresql-dev python3-dev patch
RUN python3 -m venv /usr/local/salt
COPY prerequisites.txt /
RUN pip install -r /prerequisites.txt
COPY $REQUIREMENTS /requirements.txt
RUN pip install $FLAGS -r /requirements.txt
COPY nacl.py /usr/local/salt/lib/python3.11/site-packages/salt/utils/
COPY logstash_engine.py /usr/local/salt/lib/python3.11/site-packages/salt/engines/
COPY rest_cherrypy-app.patch /tmp/rest_cherrypy-app.patch
# Apply the patch to the installed Salt package inside the venv
# (build-base pulls in 'patch' on Alpine; if not, add 'apk add patch')
RUN apk add --no-cache patch
RUN python3 - <<'PY'
import io, os, inspect, re
import salt.netapi.rest_cherrypy.app as appmod

app_path = inspect.getfile(appmod)
src = io.open(app_path, "r", encoding="utf-8").read()

# If we've already patched, bail out (idempotent)
if "BEGIN: user-configurable CherryPy merges" in src:
    print("Already patched:", app_path)
else:
    insert_after = '\n        if salt.utils.versions.version_cmp(cherrypy.__version__, "12.0.0") < 0:'
    idx = src.find(insert_after)
    if idx < 0:
        raise SystemExit("Could not find version_cmp anchor in %s" % app_path)

    block = '''
        # --- BEGIN: user-configurable CherryPy merges ---
        # Allow users to inject additional CherryPy *global* settings via:
        # rest_cherrypy:
        #   global:
        #     tools.sessions.on: True
        #     tools.sessions.storage_class: cherrypy.lib.sessions.FileSession
        #     tools.sessions.storage_path: /var/cache/salt/api/sessions
        user_global = self.apiopts.get("global", {})
        if isinstance(user_global, dict):
            conf["global"].update(user_global)

        # Allow users to inject per-root ("/") tool settings via:
        # rest_cherrypy:
        #   root:
        #     tools.sessions.on: True
        #     tools.sessions.storage_class: cherrypy.lib.sessions.FileSession
        user_root = self.apiopts.get("root", {})
        if isinstance(user_root, dict):
            conf["/"].update(user_root)

        # Convenience: accept top-level rest_cherrypy keys starting with "tools."
        # and map them onto the root path ("/") section.
        for k, v in self.apiopts.items():
            if isinstance(k, str) and k.startswith("tools."):
                conf["/"][k] = v
        # --- END: user-configurable CherryPy merges ---
'''.rstrip("\n")

    new_src = src[:idx] + block + src[idx:]
    io.open(app_path, "w", encoding="utf-8").write(new_src)
    print("Patched:", app_path)
PY
RUN find /usr/local/salt -name \*.pyc -delete && rm -f /usr/local/salt/lib/python3.11/site-packages/salt/returners/django_return.py
RUN find $VIRTUAL_ENV -type d -name __pycache__ -exec chown -v ${USER_ID}:${USER_ID} {} \;

FROM golang:alpine AS yescrypt-builder
RUN apk add --no-cache git
WORKDIR /build
COPY ./yescrypt-cli ./
RUN go mod download && CGO_ENABLED=0 go build -trimpath -ldflags="-w -s" -o yescrypt-cli .

FROM base as salt
MAINTAINER Paul Martin
ARG USER_ID=1000
COPY --from=builder /usr/local/salt /usr/local/salt
COPY --from=yescrypt-builder /build/yescrypt-cli /usr/local/bin/yescrypt-cli
RUN addgroup -g ${USER_ID} salt && \
    adduser -u ${USER_ID} -s /sbin/nologin -h /opt/salt -SD -G salt salt
RUN mkdir -p /srv /var/run/salt /etc/salt/pki/master /etc/salt/pki/minion /etc/salt/master.d /var/log/salt /var/cache/salt/master && \
    chown -R ${USER_ID}:${USER_ID} /srv /etc/salt /var/log/salt /var/cache/salt /var/run/salt && \
    ln -s /usr/lib/libpq.so.5 /usr/lib/libpq.so
WORKDIR /opt/salt
USER ${USER_ID}:${USER_ID}
ENV PYTHONUNBUFFERED=1 PATH="/usr/local/salt/bin:${PATH}" MIMIC_SALT_INSTALL=1 VIRTUAL_ENV=/usr/local/salt
ENTRYPOINT ["salt-master"]
CMD ["-l", "info"]
