FROM python:3.13-alpine AS base
MAINTAINER Paul Martin
RUN apk upgrade --update --no-cache && \
    apk add --update --no-cache ca-certificates libzmq libpq libldap libcrypto3 libssl3 openssl libgcrypt cryptsetup pcre2 binutils openssl-dev libffi gnupg libgit2 libssh2 krb5 krb5-libs openssh-client-default openssh-client-common rsync

FROM base as builder
MAINTAINER Paul Martin
ARG REQUIREMENTS=requirements-3006-isalt.txt
ARG FLAGS
ARG USER_ID=1000
ENV PYTHONUNBUFFERED=1 PATH="/usr/local/salt/bin:${PATH}" GENERATE_SALT_SYSPATHS=1 VIRTUAL_ENV=/usr/local/salt

RUN apk add --update --no-cache alpine-sdk musl-dev zeromq-dev libpq-dev openldap-dev gcc libc-dev linux-headers libffi-dev libgit2-dev libssh2-dev rust cargo wget tar git build-base krb5-dev postgresql-dev python3-dev
RUN python3 -m venv /usr/local/salt
COPY prerequisites.txt /
RUN pip install -r /prerequisites.txt
COPY $REQUIREMENTS /requirements.txt
RUN pip install $FLAGS -r /requirements.txt
COPY nacl.py /usr/local/salt/lib/python3.13/site-packages/salt/utils/
COPY logstash_engine.py /usr/local/salt/lib/python3.13/site-packages/salt/engines/
#RUN rm -fv /usr/local/salt/lib/python3.12/site-packages/salt/modules/vsphere.py
RUN find /usr/local/salt -name \*.pyc -delete && rm -f /usr/local/salt/lib/python3.13/site-packages/salt/returners/django_return.py
RUN find $VIRTUAL_ENV -type d -name __pycache__ -exec chown -v ${USER_ID}:${USER_ID} {} \;

FROM base as salt
MAINTAINER Paul Martin
ARG USER_ID=1000
COPY --from=builder /usr/local/salt /usr/local/salt
RUN addgroup -g ${USER_ID} salt && \
    adduser -u ${USER_ID} -s /sbin/nologin -h /opt/salt -SD -G salt salt
RUN mkdir -p /srv /var/run/salt /etc/salt/pki/master /etc/salt/pki/minion /etc/salt/master.d /var/log/salt /var/cache/salt/master && \
    chown -R ${USER_ID}:${USER_ID} /srv /etc/salt /var/log/salt /var/cache/salt /var/run/salt
WORKDIR /opt/salt
USER ${USER_ID}:${USER_ID}
ENV PYTHONUNBUFFERED=1 PATH="/usr/local/salt/bin:${PATH}" MIMIC_SALT_INSTALL=1 VIRTUAL_ENV=/usr/local/salt
ENTRYPOINT ["salt-master"]
CMD ["-l", "info"]
