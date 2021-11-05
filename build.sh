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

IMAGE_NAME=${IMAGE_NAME:-docker.io/elchenberg/smtp-sink}
TARGET_BUSYBOX=busybox
TARGET_DISTROLESS=distroless

BUSYBOX_VERSION=${BUSYBOX_VERSION:-1.34}
DEBIAN_VERSION=${DEBIAN_VERSION:-unstable-20211011-slim}
POSTFIX_VERSION=${POSTFIX_VERSION:-3.6.2}
TINI_VERSION=${TINI_VERSION:-0.19.0}

PLATFORMS=${PLATFORMS:-linux/386,linux/amd64,linux/arm/v6,linux/arm/v7,linux/arm64,linux/mips64le,linux/ppc64le,linux/riscv64,linux/s390x}

PUSH=${PUSH:-false}

buildctl-daemonless.sh build \
  --export-cache "dest=${PWD:?}/.cache,type=local" \
  --frontend "dockerfile.v0" \
  --import-cache "src=${PWD:?}/.cache,type=local" \
  --local "context=${PWD:?}" \
  --local "dockerfile=${PWD:?}" \
  --opt "build-arg:BUSYBOX_VERSION=${BUSYBOX_VERSION:?}" \
  --opt "build-arg:DEBIAN_VERSION=${DEBIAN_VERSION:?}" \
  --opt "build-arg:POSTFIX_VERSION=${POSTFIX_VERSION:?}" \
  --opt "build-arg:TINI_VERSION=${TINI_VERSION}" \
  --opt "filename=Dockerfile" \
  --opt "platform=${PLATFORMS:?}" \
  --opt "target=${TARGET_BUSYBOX:?}" \
  --output "type=image,name=${IMAGE_NAME:?}:${POSTFIX_VERSION:?}-${TARGET_BUSYBOX:?},push=${PUSH:?}"
buildctl-daemonless.sh prune

buildctl-daemonless.sh build \
  --export-cache "dest=${PWD:?}/.cache,type=local" \
  --frontend "dockerfile.v0" \
  --import-cache "src=${PWD:?}/.cache,type=local" \
  --local "context=${PWD:?}" \
  --local "dockerfile=${PWD:?}" \
  --opt "build-arg:BUSYBOX_VERSION=${BUSYBOX_VERSION:?}" \
  --opt "build-arg:DEBIAN_VERSION=${DEBIAN_VERSION:?}" \
  --opt "build-arg:POSTFIX_VERSION=${POSTFIX_VERSION:?}" \
  --opt "build-arg:TINI_VERSION=${TINI_VERSION}" \
  --opt "filename=Dockerfile" \
  --opt "platform=${PLATFORMS:?}" \
  --opt "target=${TARGET_DISTROLESS:?}" \
  --output "type=image,name=${IMAGE_NAME:?}:${POSTFIX_VERSION:?},push=${PUSH:?}"
buildctl-daemonless.sh prune
