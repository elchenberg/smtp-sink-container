#!/usr/bin/env bash

set -o errexit
set -o nounset

if set +o | grep -Fq 'set +o pipefail'; then
  set -o pipefail
fi

if set +o | grep -Fq 'set +o posix'; then
  set -o posix
fi

set -o xtrace

DIRECTORY="$(
  cd -- "$(dirname "${0:?}")" >/dev/null 2>&1 || exit 1
  pwd -P
)"

IMAGE_REPO=${IMAGE_REPO:-docker.io/elchenberg/smtp-sink}
TARGET_BUSYBOX=busybox
TARGET_DISTROLESS=distroless

BUSYBOX_VERSION=${BUSYBOX_VERSION:-1.34}
DEBIAN_VERSION=${DEBIAN_VERSION:-unstable-20211011-slim}
POSTFIX_VERSION=${POSTFIX_VERSION:-3.6.2}
TINI_VERSION=${TINI_VERSION:-0.19.0}

PLATFORMS=${PLATFORMS:-linux/386,linux/amd64,linux/arm/v6,linux/arm/v7,linux/arm64,linux/mips64le,linux/ppc64le,linux/s390x}

PUSH=${PUSH:-false}

unset BUILD_TARGET
unset IMAGE_NAME

build() {
  buildctl-daemonless.sh build \
    --export-cache "dest=${DIRECTORY:?}/.cache,mode=max,type=local" \
    --frontend "dockerfile.v0" \
    --import-cache "src=${DIRECTORY:?}/.cache,type=local" \
    --local "context=${DIRECTORY:?}" \
    --local "dockerfile=${DIRECTORY:?}" \
    --opt "build-arg:BUSYBOX_VERSION=${BUSYBOX_VERSION:?}" \
    --opt "build-arg:DEBIAN_VERSION=${DEBIAN_VERSION:?}" \
    --opt "build-arg:POSTFIX_VERSION=${POSTFIX_VERSION:?}" \
    --opt "build-arg:TINI_VERSION=${TINI_VERSION}" \
    --opt "filename=Dockerfile" \
    --opt "platform=${PLATFORMS:?}" \
    --opt "target=${BUILD_TARGET:?}" \
    --output "type=image,name=${IMAGE_NAME:?},push=${PUSH:?}"
}

BUILD_TARGET="${TARGET_BUSYBOX:?}" IMAGE_NAME="${IMAGE_REPO:?}:${POSTFIX_VERSION:?}-${TARGET_BUSYBOX:?}" build
buildctl-daemonless.sh prune || true

BUILD_TARGET="${TARGET_DISTROLESS:?}" IMAGE_NAME="${IMAGE_REPO:?}:${POSTFIX_VERSION:?}" build
buildctl-daemonless.sh prune || true
