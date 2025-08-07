# yescrypt-cli

A minimal, statically linked Go CLI utility for generating and verifying yescrypt password hashes.

## Features

- ✅ **Generate yescrypt hashes** for passwords (random or user-supplied)
- ✅ **Verify** a password against an existing yescrypt hash
- ✅ Output is **JSON-formatted** for easy parsing in automation
- ✅ Portable: can be statically compiled with `CGO_ENABLED=0` for use in Alpine-based or glibc-less containers
- ✅ Suitable for use in Salt runners or other password rotation workflows

## Usage

```bash
# Generate a password and its yescrypt hash
yescrypt-cli gen

# Generate a hash for a specific password
yescrypt-cli gen --password "hunter2"

# Verify a password against a hash
yescrypt-cli verify --password "hunter2" --hash '$y$j9T$saltsaltsalt$...'
