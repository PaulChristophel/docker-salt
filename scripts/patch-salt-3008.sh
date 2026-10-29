#!/bin/sh
# Temporary workaround for https://github.com/saltstack/salt/issues/70592.
set -eu

salt_python="${1:-/usr/local/salt/bin/python}"
salt_major="$("$salt_python" -c 'import salt.version; print(salt.version.__version_info__[0])')"
case "$salt_major" in
    3008)
        salt_dir="$("$salt_python" -c 'import pathlib, salt; print(pathlib.Path(salt.__file__).parent)')"
        patch --batch --forward --fuzz=0 -d "$salt_dir" -p1 < /tmp/salt-70592.patch
        ;;
    *)
        echo "Skipping Salt 3008 router patch for Salt $salt_major"
        ;;
esac
