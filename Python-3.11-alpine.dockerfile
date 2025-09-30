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
RUN python3 - <<'PY'
import io, re, inspect
import salt.netapi.rest_cherrypy.app as appmod

app_path = inspect.getfile(appmod)
src = io.open(app_path, "r", encoding="utf-8").read()

# bail out if already patched (idempotent)
if "BEGIN: user-configurable CherryPy merges" in src:
    print("Already patched:", app_path)
else:
    new_fn = r'''
def get_conf(self):
    """
    Combine the CherryPy configuration with the rest_cherrypy config values
    pulled from the master config and return the CherryPy configuration
    """
    conf = {
        "global": {
            "server.socket_host": self.apiopts.get("host", "0.0.0.0"),
            "server.socket_port": self.apiopts.get("port", 8000),
            "server.thread_pool": self.apiopts.get("thread_pool", 100),
            "server.socket_queue_size": self.apiopts.get("queue_size", 30),
            "max_request_body_size": self.apiopts.get("max_request_body_size", 1048576),
            "debug": self.apiopts.get("debug", False),
            "log.access_file": self.apiopts.get("log_access_file", ""),
            "log.error_file": self.apiopts.get("log_error_file", ""),
        },
        "/": {
            "request.dispatch": cherrypy.dispatch.MethodDispatcher(),
            "tools.trailing_slash.on": True,
            "tools.gzip.on": True,
            "tools.html_override.on": True,
            "tools.cors_tool.on": True,
        },
    }

    # --- BEGIN: user-configurable CherryPy merges ---
    # Allow extra CherryPy *global* keys via:
    # rest_cherrypy:
    #   global:
    #     tools.sessions.on: True
    #     tools.sessions.storage_class: cherrypy.lib.sessions.FileSession
    #     tools.sessions.storage_path: /var/cache/salt/api/sessions
    user_global = self.apiopts.get("global", {})
    if isinstance(user_global, dict):
        conf["global"].update(user_global)

    # Allow extra root ("/") tool/path keys via:
    # rest_cherrypy:
    #   root:
    #     tools.sessions.on: True
    #     tools.sessions.storage_class: cherrypy.lib.sessions.FileSession
    user_root = self.apiopts.get("root", {})
    if isinstance(user_root, dict):
        conf["/"].update(user_root)

    # Convenience: map any top-level rest_cherrypy keys starting with "tools."
    # onto the root ("/") section.
    for k, v in self.apiopts.items():
        if isinstance(k, str) and k.startswith("tools."):
            conf["/"][k] = v
    # --- END: user-configurable CherryPy merges ---

    if salt.utils.versions.version_cmp(cherrypy.__version__, "12.0.0") < 0:
        conf["global"]["engine.timeout_monitor.on"] = self.apiopts.get("expire_responses", True)

    if cpstats and self.apiopts.get("collect_stats", False):
        conf["/"]["tools.cpstats.on"] = True

    if "favicon" in self.apiopts:
        conf["/favicon.ico"] = {
            "tools.staticfile.on": True,
            "tools.staticfile.filename": self.apiopts["favicon"],
        }

    if self.apiopts.get("debug", False) is False:
        conf["global"]["environment"] = "production"

    if "static" in self.apiopts:
        conf[self.apiopts.get("static_path", "/static")] = {
            "tools.staticdir.on": True,
            "tools.staticdir.dir": self.apiopts["static"],
        }

    cherrypy.config.update(conf["global"])
    return conf
'''.lstrip("\n")

    # replace the existing get_conf(...) block (from def ... to the matching 'return conf')
    pattern = re.compile(r'\ndef\\s+get_conf\\s*\\(\\s*self\\s*\\)\\s*:\\s*.*?\\n\\s*return\\s+conf\\s*\\n', re.DOTALL)
    new_src, n = pattern.subn("\\n"+new_fn+"\\n", src)
    if n != 1:
        raise SystemExit(f"get_conf() replacement failed; matched {n} blocks in {app_path}")
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
