# Salt master container images

This repository builds compact, non-root Salt master images with the Python
dependencies and system libraries needed for the project's operational Salt
modules. Published images are available from
[`docker.io/pcm0/salt`](https://hub.docker.com/r/pcm0/salt).

## Image matrix

`images.json` is the source of truth for the release workflow. It defines the
supported Python versions, Salt release channels, dependency profiles, base
operating systems, and image repository. `scripts/generate_matrix.py` validates
that configuration, checks stable Salt pins against the requirements files,
and expands the supported combinations for GitHub Actions.

The current matrix contains:

- Python 3.11 through 3.14 on Debian slim;
- Python 3.14 on Photon OS 5;
- stable Salt 3006 and 3008 releases;
- development snapshots from the `3006.x`, `3008.x`, and `master` branches;
- a standard profile and an `isalt` profile with interactive Salt tooling;
- `linux/amd64` as the current publication platform.

Photon builds are limited to Salt 3008, `3008.x`, and `master`. The Alpine
Dockerfile remains available for local experimentation, but Alpine images are
not part of the published matrix.

## Included capabilities

The dependency sets are designed for a Salt master that uses:

- `salt-ssh` and OpenSSH clients;
- LDAP and Kerberos authentication;
- GPG-encrypted pillar data;
- PostgreSQL returners and event data;
- Git-backed fileserver and pillar sources;
- REST CherryPy, logging, and OpenTelemetry integrations;
- Ansible execution modules.

The image also installs the repository's Salt compatibility modules for NaCl,
the Logstash engine, and the REST CherryPy application. The `isalt` profile
adds IPython and `isalt`; it does not change the Salt release being installed.

## Tags

Tags describe Python, Salt, profile, operating system, and release channel:

```text
3.14-3008-debian
3.14-3008.2-isalt-debian
3.14-3008.x-photon-dev
3.14-master-1a2b3c4-isalt-debian-dev
```

Stable builds publish both a Salt feature-line tag such as `3008` and a full
Salt version tag such as `3008.2`. Every build also publishes a seven-character
Git SHA tag. Development tags end in `-dev` and track their upstream Salt Git
branch, so the SHA form is preferable when a repeatable deployment is needed.
No generic `latest` tag is published because it would hide the Python, Salt,
profile, and operating-system choices.

## Running an image

The final image runs as user and group ID `1000` and starts `salt-master`
through `tini`. Mount the master configuration, PKI, and Salt state trees at
the paths expected by Salt:

```sh
/opt/homebrew/bin/podman run --rm \
  --name salt-master \
  --publish 4505:4505 \
  --publish 4506:4506 \
  --volume ./master.d:/etc/salt/master.d:ro \
  --volume ./pki:/etc/salt/pki/master \
  --volume ./srv:/srv:ro \
  docker.io/pcm0/salt:3.14-3008-debian
```

Ensure writable mounts are owned by UID/GID `1000`. Production deployments
should persist `/etc/salt/pki/master` so the master's identity is not recreated
when the container is replaced.

## Building locally

The Dockerfiles accept the same inputs used by the release matrix. For example:

```sh
/opt/homebrew/bin/podman build \
  --platform linux/amd64 \
  --file Python-debian.dockerfile \
  --build-arg PYTHON_RELEASE=3.14-slim \
  --build-arg PYTHONPATH=/usr/local/salt/lib/python3.14 \
  --build-arg REQUIREMENTS=requirements-3008.txt \
  --build-arg 'FLAGS=--no-deps' \
  --tag localhost/salt:3.14-3008-debian \
  .
```

The dependency files are deliberately explicit and pinned. Update the
appropriate `requirements-*.txt` pair together when changing either a standard
and `isalt` image for the same Salt channel.

## Release process

The GitHub Actions release workflow expands `images.json` into the supported
Python × Salt × profile × operating-system combinations. It runs on relevant
changes to `master`, once per day for development refreshes, and on manual
dispatch. Each matrix job builds with Podman and publishes its moving,
versioned where applicable, and Git-SHA tags to Docker Hub.
