# Directory of Makefile
export ROOT_DIR:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

DISK?=$(shell ls $(ROOT_DIR)/build/*.qcow2 2> /dev/null)
DISKSIZE?=20G
ISO?=$(shell ls $(ROOT_DIR)/build/*.iso 2> /dev/null)
FLAVOR?=green
ARCH?=$(shell uname -m)
PLATFORM?=linux/$(ARCH)
IMAGE_SIZE?=20G
REPO?=local/elemental-$(FLAVOR)
TOOLKIT_REPO?=local/elemental-toolkit
DOCKER?=docker
BASE_OS_IMAGE?=registry.opensuse.org/opensuse/leap
BASE_OS_VERSION?=15.5
DOCKER_SOCK?=/var/run/docker.sock

GIT_COMMIT?=$(shell git rev-parse HEAD)
GIT_COMMIT_SHORT?=$(shell git rev-parse --short HEAD)
GIT_TAG?=$(shell git describe --candidates=50 --abbrev=0 --tags 2>/dev/null || echo "v0.0.1" )
VERSION?=$(GIT_TAG)-g$(GIT_COMMIT_SHORT)

PKG:=./cmd ./pkg/...
LDFLAGS:=-w -s
LDFLAGS+=-X "github.com/rancher/elemental-toolkit/internal/version.version=$(GIT_TAG)"
LDFLAGS+=-X "github.com/rancher/elemental-toolkit/internal/version.gitCommit=$(GIT_COMMIT)"

# For RISC-V 64bit support
ifeq ($(PLATFORM),linux/riscv64)
BASE_OS_IMAGE=registry.opensuse.org/opensuse/factory/riscv/images/opensuse/tumbleweed
BASE_OS_VERSION=latest
ifeq ($(FLAVOR),tumbleweed)
OS_IMAGE=registry.opensuse.org/opensuse/factory/riscv/images/opensuse/tumbleweed
ADD_REPO=https://download.opensuse.org/repositories/devel:/RISCV:/Factory:/Contrib:/StarFive:/VisionFive2/standard
BUILD_OPTS=--build-arg OS_IMAGE=$(OS_IMAGE) --build-arg ADD_REPO=$(ADD_REPO)
endif
endif

# default target
.PHONY: all
all: build build-cli

#----------------------- includes -----------------------

include make/Makefile.test

#----------------------- targets ------------------------

.PHONY: build
build:
	$(DOCKER) build --platform $(PLATFORM) ${DOCKER_ARGS} \
			--build-arg ELEMENTAL_VERSION=$(GIT_TAG) \
			--build-arg ELEMENTAL_COMMIT=$(GIT_COMMIT) \
			--build-arg BASE_OS_IMAGE=$(BASE_OS_IMAGE) \
			--build-arg BASE_OS_VERSION=$(BASE_OS_VERSION) \
			--target elemental-toolkit -t $(TOOLKIT_REPO):$(VERSION) .

.PHONY: push-toolkit
push-toolkit:
	$(DOCKER) push $(TOOLKIT_REPO):$(VERSION)

.PHONY: build-cli
#build-cli:
#	go build -ldflags '$(LDFLAGS)' -o build/elemental
build-cli: ## build elemental CLI
	VERSION=$(VERSION) \
	goreleaser release --snapshot --clean

.PHONY: release-cli
release-cli: ## build elemental CLI
	VERSION=$(VERSION) \
	goreleaser release --clean

.PHONY: build-os
build-os: build
	$(DOCKER) build --platform $(PLATFORM) ${DOCKER_ARGS} \
			--build-arg TOOLKIT_REPO=$(TOOLKIT_REPO) \
			--build-arg VERSION=$(VERSION) \
			--build-arg REPO=$(REPO) -t $(REPO):$(VERSION) \
			$(BUILD_OPTS) examples/$(FLAVOR)

.PHONY: push-os
push-os:
	$(DOCKER) push $(REPO):$(VERSION)

.PHONY: build-iso
build-iso: build-os
	@echo Building $(ARCH) ISO
	mkdir -p $(ROOT_DIR)/build
	$(DOCKER) run --rm -v $(DOCKER_SOCK):$(DOCKER_SOCK) -v $(ROOT_DIR)/build:/build \
		--entrypoint /usr/bin/elemental $(TOOLKIT_REPO):$(VERSION) --debug build-iso --bootloader-in-rootfs -n elemental-$(FLAVOR).$(ARCH) \
		--local --platform $(PLATFORM) --squash-no-compression -o /build $(REPO):$(VERSION)

.PHONY: build-disk
build-disk: build-os
	@echo Building $(ARCH) disk
	mkdir -p $(ROOT_DIR)/build
	$(DOCKER) run --rm -v $(DOCKER_SOCK):$(DOCKER_SOCK) -v $(ROOT_DIR)/build:/build \
		--entrypoint /usr/bin/elemental \
		$(TOOLKIT_REPO):$(VERSION) --debug build-disk --platform $(PLATFORM) --unprivileged --expandable -n elemental-$(FLAVOR).$(ARCH) --local \
		--squash-no-compression -o /build $(REPO):$(VERSION)
	qemu-img convert -O qcow2 $(ROOT_DIR)/build/elemental-$(FLAVOR).$(ARCH).raw $(ROOT_DIR)/build/elemental-$(FLAVOR).$(ARCH).qcow2
	qemu-img resize $(ROOT_DIR)/build/elemental-$(FLAVOR).$(ARCH).qcow2 $(DISKSIZE) 

.PHONY: build-rpi-disk
build-rpi-disk: build-os
ifneq ("$(PLATFORM)","linux/arm64")
	@echo "Cannot build Raspberry Pi disk for $(PLATFORM)"
	@exit 1
endif
	@echo Building $(ARCH) disk
	mkdir -p $(ROOT_DIR)/build
	$(DOCKER) run --rm -v $(DOCKER_SOCK):$(DOCKER_SOCK) -v $(ROOT_DIR)/examples:/examples -v $(ROOT_DIR)/build:/build \
		--entrypoint /usr/bin/elemental \
		$(TOOLKIT_REPO):$(VERSION) --debug build-disk --platform $(PLATFORM) --cloud-init-paths /examples/$(FLAVOR) --unprivileged --expandable -n elemental-$(FLAVOR).aarch64 --local \
		--squash-no-compression --deploy-command elemental,--debug,reset,--reboot,--disable-boot-entry -o /build $(REPO):$(VERSION)

PHONY: build-vf2-disk
build-vf2-disk: build-os
ifneq ("$(PLATFORM)","linux/riscv64")
	@echo "Cannot build VisionFive2 disk for $(PLATFORM)"
	@exit 1
endif
	@echo Building $(ARCH) disk
	mkdir -p $(ROOT_DIR)/build
	$(DOCKER) run --rm -v $(DOCKER_SOCK):$(DOCKER_SOCK) -v $(ROOT_DIR)/examples:/examples -v $(ROOT_DIR)/build:/build \
		--entrypoint /usr/bin/elemental \
		$(TOOLKIT_REPO):$(VERSION) --debug build-disk --platform $(PLATFORM) --cloud-init-paths /examples/$(FLAVOR) --unprivileged --expandable -n elemental-$(FLAVOR).riscv64 --local \
		--squash-no-compression --deploy-command elemental,--debug,reset,--reboot,--disable-boot-entry -o /build $(REPO):$(VERSION)

.PHONY: clean
clean:
	rm -fv $(ROOT_DIR)/build/elemental-$(FLAVOR).$(ARCH).{raw,img,qcow2,iso,iso.sha256}

.PHONY: vet
vet:
	go vet $(PKG)

.PHONY: fmt
fmt:
ifneq ($(shell go fmt $(PKG)),)
	@echo "Please commit the changes from 'make fmt'"
	@exit 1
else
	@echo "All files formatted"
	@exit 0
endif

.PHONY: license-check
license-check:
	@.github/license_check.sh

.PHONY: lint
lint: fmt vet

.PHONY: build-docs
build-docs:
	@./scripts/docs-build.sh
	cd docs && go run generate_docs.go
