# Makefile for yescrypt-cli

BINARY_NAME := yescrypt-cli
ENV ?= debug

# Defaults for portable builds (can be overridden at runtime)
PORTABLE_OS ?= linux
PORTABLE_ARCH ?= amd64

ifeq ($(ENV),prod)
	BUILD_FLAGS := -trimpath -ldflags="-w -s"
else
	BUILD_FLAGS :=
endif

.PHONY: all build clean run test fmt lint tidy upgrade portable

all: build

build:
	go build $(BUILD_FLAGS) -o $(BINARY_NAME) .

clean:
	rm -f $(BINARY_NAME) $(BINARY_NAME)-static

run: build
	./$(BINARY_NAME)

test:
	go test -cover ./...

fmt:
	go fmt ./...

lint:
	golangci-lint run ./...

tidy:
	go mod tidy

upgrade:
	go get -u ./...

portable:
	GOOS=$(PORTABLE_OS) GOARCH=$(PORTABLE_ARCH) CGO_ENABLED=0 go build $(BUILD_FLAGS) -o $(BINARY_NAME) .
