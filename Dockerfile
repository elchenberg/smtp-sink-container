ARG BUSYBOX_VERSION
ARG DEBIAN_VERSION

# hadolint ignore=DL3029
FROM --platform=${BUILDPLATFORM:-linux/amd64} debian:${DEBIAN_VERSION:-unstable-20211011-slim} AS base
SHELL [ "/bin/bash", "-euxo", "pipefail", "-c" ]
# hadolint ignore=DL3008
RUN \
    apt-get update; \
    apt-get upgrade --assume-yes; \
    apt-get install --assume-yes --no-install-recommends \
      ca-certificates \
      cmake \
      curl \
      file \
      gnupg \
      make \
      ; \
    apt-get clean; \
    rm --force --recursive /var/lib/apt/lists/* /var/log/apt/history.log /var/log/dpkg.log


FROM base AS source
SHELL [ "/bin/bash", "-euxo", "pipefail", "-c" ]
ARG POSTFIX_VERSION
ENV POSTFIX_VERSION=${POSTFIX_VERSION:-3.6.2}
ENV POSTFIX_KEY_FINGERPRINT=622C7C012254C186677469C50C0B590E80CA15A7
ARG TINI_VERSION
ENV TINI_VERSION=${TINI_VERSION:-0.19.0}
RUN \
    GNUPGHOME="$(mktemp --directory)"; \
    export GNUPGHOME="${GNUPGHOME:?}"; \
    gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "${POSTFIX_KEY_FINGERPRINT:?}"; \
    printf "%s:6:\n" "${POSTFIX_KEY_FINGERPRINT:?}" | gpg --import-ownertrust; \
    curl \
      --fail \
      --location \
      --output postfix.tar.gz.gpg2 \
      --show-error \
      --silent \
      --tlsv1.3 \
      "https://de.postfix.org/ftpmirror/official/postfix-${POSTFIX_VERSION:?}.tar.gz.gpg2" \
      ; \
    curl \
      --fail \
      --location \
      --output postfix.tar.gz \
      --show-error \
      --silent \
      --tlsv1.3 \
      "https://de.postfix.org/ftpmirror/official/postfix-${POSTFIX_VERSION:?}.tar.gz" \
      ; \
    gpg --batch --verify "postfix.tar.gz.gpg2" "postfix.tar.gz"; \
    mkdir postfix; \
    tar \
      --directory=postfix \
      --extract \
      --gzip \
      --no-same-owner \
      --no-same-permissions \
      --strip-components=1 \
      --file=postfix.tar.gz \
      "postfix-${POSTFIX_VERSION:?}/bin" \
      "postfix-${POSTFIX_VERSION:?}/conf" \
      "postfix-${POSTFIX_VERSION:?}/include" \
      "postfix-${POSTFIX_VERSION:?}/lib" \
      "postfix-${POSTFIX_VERSION:?}/libexec" \
      "postfix-${POSTFIX_VERSION:?}/makedefs" \
      "postfix-${POSTFIX_VERSION:?}/Makefile.in" \
      "postfix-${POSTFIX_VERSION:?}/Makefile.init" \
      "postfix-${POSTFIX_VERSION:?}/Makefile" \
      "postfix-${POSTFIX_VERSION:?}/meta" \
      "postfix-${POSTFIX_VERSION:?}/src/global" \
      "postfix-${POSTFIX_VERSION:?}/src/smtpstone" \
      "postfix-${POSTFIX_VERSION:?}/src/util" \
      ; \
    rm --force postfix.tar.gz postfix.tar.gz.gpg2; \
    curl \
      --fail \
      --location \
      --output tini.tar.gz \
      --show-error \
      --silent \
      --tlsv1.3 \
      "https://github.com/krallin/tini/archive/refs/tags/v${TINI_VERSION:?}.tar.gz" \
      ; \
    mkdir tini; \
    tar \
      --directory=tini \
      --extract \
      --gzip \
      --no-same-owner \
      --no-same-permissions \
      --strip-components=1 \
      --file=tini.tar.gz \
      "tini-${TINI_VERSION:?}/CMakeLists.txt" \
      "tini-${TINI_VERSION:?}/LICENSE" \
      "tini-${TINI_VERSION:?}/src" \
      "tini-${TINI_VERSION:?}/tpl" \
      ; \
    rm --force tini.tar.gz


FROM source AS binaries
SHELL [ "/bin/bash", "-euxo", "pipefail", "-c" ]
ARG TARGETPLATFORM
ENV TARGETPLATFORM=${TARGETPLATFORM:-linux/amd64}
# hadolint ignore=DL3008
RUN \
    #
    # detect supported target platforms
    #
    case "${TARGETPLATFORM:?}" in \
      linux/386) DPKG_ARCH=i386 ;; \
      linux/amd64) DPKG_ARCH=amd64 ;; \
      linux/arm/v6) DPKG_ARCH=armel ;; \
      linux/arm/v7) DPKG_ARCH=armhf ;; \
      linux/arm64) DPKG_ARCH=arm64 ;; \
      linux/arm64/v8) DPKG_ARCH=arm64 ;; \
      linux/mips64le) DPKG_ARCH=mips64el ;; \
      linux/ppc64le) DPKG_ARCH=ppc64el ;; \
      linux/s390x) DPKG_ARCH=s390x ;; \
      *) \
        echo "${TARGETPLATFORM:?} not supported"; \
        exit 1; \
        ;; \
    esac; \
    #
    # install cross build dependencies
    #
    if test "$(dpkg --print-architecture)" != "${DPKG_ARCH:?}"; then \
      dpkg --add-architecture "${DPKG_ARCH:?}"; \
    fi; \
    apt-get update; \
    apt-get upgrade --assume-yes; \
    apt-get install --assume-yes --no-install-recommends \
      "libc6-dev-${DPKG_ARCH:?}-cross" \
      "musl-tools:${DPKG_ARCH:?}" \
      ; \
    #
    # build tini
    #
    CC="musl-gcc -static -s"; \
    CFLAGS="-Ofast -DPR_SET_CHILD_SUBREAPER=36 -DPR_GET_CHILD_SUBREAPER=37"; \
    CC="${CC:?}" CFLAGS="${CFLAGS:?}" cmake -S tini -B tini-build; \
    make --directory=tini-build; \
    #
    # verify that the binary is statically linked and stripped
    #
    file --brief tini-build/tini-static | \
      grep --fixed-strings --quiet 'statically linked'; \
    file --brief tini-build/tini-static | \
      grep --fixed-strings --invert-match --quiet 'not stripped'; \
    #
    # install the binary
    #
    install -D --mode=755 \
      tini-build/tini-static \
      /usr/local/bin/tini; \
    #
    # clean up the build directory
    #
    rm --force --recursive tini-build; \
    #
    # prepare the postfix build
    #
    # - find the musl include directory
    INCLUDE_DIR="$( \
      find /usr -type d -name '*linux-musl*' | \
        grep --fixed-strings '/include' | \
        head --lines=1 \
    )"; \
    # - symlink the gnu "linux/version.h" header file into the musl include directory
    if ! test -f "${INCLUDE_DIR:?}/linux/version.h"; then \
      LINUX_VERSION_HEADER="$( \
        find /usr -type f -name 'version.h' | \
          grep --fixed-strings '/linux/version.h' | \
          head --lines=1 \
      )"; \
      mkdir --parents "${INCLUDE_DIR:?}/linux"; \
      ln --symbolic "${LINUX_VERSION_HEADER:?}" "${INCLUDE_DIR:?}/linux/version.h"; \
    fi; \
    # - ar is not installed with the usual name but as $ARCH-linux-gnu-gcc-ar
    if ! test -x /usr/bin/ar; then \
      AR="$( \
        find /usr -type f -executable -name '*-ar' | \
          head --lines=1 \
      )"; \
      ln --symbolic "${AR:?}" /usr/bin/ar; \
    fi; \
    # - ranlib, too, is not installed with the usual name but as $ARCH-linux-gnu-gcc-ranlib
    if ! test -x /usr/bin/ranlib; then \
      RANLIB="$( \
        find /usr -type f -executable -name '*-ranlib' | \
          head --lines=1 \
      )"; \
      ln --symbolic "${RANLIB:?}" /usr/bin/ranlib; \
    fi; \
    #
    # build postfix
    #
    CC="musl-gcc -static -s"; \
    CCARGS="-DNO_DB -DNO_NIS"; \
    DIRS="src/util src/global src/smtpstone"; \
    OPT="-Ofast"; \
    make --directory=postfix --silent makefiles CC="${CC:?}" CCARGS="${CCARGS:?}" DEBUG= DIRS="${DIRS:?}" OPT="${OPT:?}"; \
    make --directory=postfix --silent DIRS="${DIRS:?}"; \
    #
    # verify that the binary is statically linked and stripped
    #
    file --brief postfix/bin/smtp-sink | \
      grep --fixed-strings --quiet 'statically linked'; \
    file --brief postfix/bin/smtp-sink | \
      grep --fixed-strings --invert-match --quiet 'not stripped'; \
    #
    # install the binary
    #
    install -D --mode=755 \
      postfix/bin/smtp-sink \
      /usr/local/bin/smtp-sink; \
    #
    # clean up the build directory
    #
    make --directory=postfix --silent tidy DIRS="${DIRS:?}"; \
    #
    # uninstall the cross build depedencies
    #
    rm --recursive "${INCLUDE_DIR:?}/linux"; \
    awk '{if($3=="install"){print $4}}' /var/log/dpkg.log | \
      xargs --verbose apt-get remove --assume-yes --autoremove --purge; \
    apt-get clean; \
    if dpkg --print-foreign-architectures | grep --fixed-strings --quiet "${DPKG_ARCH:?}"; then \
      dpkg --remove-architecture "${DPKG_ARCH:?}"; \
    fi; \
    rm --force --recursive /var/lib/apt/lists/* /var/log/apt/history.log /var/log/dpkg.log


FROM debian:${DEBIAN_VERSION:-unstable-20211011-slim} AS debian-tests
SHELL [ "/bin/bash", "-euxo", "pipefail", "-c" ]
# hadolint ignore=DL3008
RUN \
    apt-get update; \
    apt-get install --assume-yes --no-install-recommends \
      curl \
      netcat-traditional \
      ; \
    apt-get clean; \
    rm --force --recursive /var/lib/apt/lists/* /var/log/apt/history.log /var/log/dpkg.log
COPY --from=binaries /usr/local/bin/smtp-sink /usr/local/bin/tini /usr/local/bin/
USER 65534:65534
RUN \
    # 1. start smtp-sink in a subprocess
    # 2. wait until the port is open
    # 3. send a test email
    sh -euc 'tini -s -- smtp-sink 0.0.0.0:1025 128 &'; \
    timeout 5 sh -euc 'until nc -z 127.0.0.1 1025; do sleep 0.1; done'; \
    printf 'Subject: Test' | \
      curl --silent --show-error \
        --url 'smtp://127.0.0.1:1025' \
        --mail-from 'sender@localhost' \
        --mail-rcpt 'recipient@localhost' \
        --upload-file -; \
    # same as the first test, but this time the test email gets dumped to a file; \
    sh -euc 'tini -s -- smtp-sink -d "/tmp/smtp-sink/%M" 0.0.0.0:1026 128 &'; \
    timeout 5 sh -euc 'until nc -z 127.0.0.1 1026; do sleep 0.1; done'; \
    printf 'Subject: Test' | \
      curl --silent --show-error \
        --url 'smtp://127.0.0.1:1026' \
        --mail-from 'sender@localhost' \
        --mail-rcpt 'recipient@localhost' \
        --upload-file -; \
    timeout 5 sh -euc 'until cat /tmp/smtp-sink/*; do sleep 0.1; done'; \
    grep --quiet 'Subject: Test' /tmp/smtp-sink/*; \
    rm --force --recursive /tmp/smtp-sink
ONBUILD USER 0:0


FROM busybox:${BUSYBOX_VERSION:-1.34} AS busybox-tests
SHELL [ "/bin/ash", "-euxo", "pipefail", "-c" ]
COPY --from=debian-tests /usr/local/bin/smtp-sink /usr/local/bin/tini /usr/local/bin/
USER 65534:65534
RUN \
    # 1. start smtp-sink in a subprocess
    # 2. wait until the port is open
    # 3. send a test email
    (tini -s -- smtp-sink 0.0.0.0:1025 128 &); \
    timeout 5 sh -euc "until nc -v -z 127.0.0.1 1025; do sleep 0.1; done"; \
    printf 'Subject: Test' | \
      sendmail -f sender@localhost -S 127.0.0.1:1025 -v recipient@localhost 2>&1 | \
      tee /dev/stderr | grep -Fi 'error' && false; \
    # same as the first test, but this time the test email gets dumped to a file
    (tini -s -vvv -- smtp-sink -d "/tmp/smtp-sink/%M" -v 0.0.0.0:1026 128 &); \
    timeout 5 sh -euc "until nc -v -z 127.0.0.1 1026; do sleep 0.1; done"; \
    printf 'Subject: Test' | \
      sendmail -f sender@localhost -S 127.0.0.1:1026 -v recipient@localhost 2>&1 | \
      tee /dev/stderr | grep -Fi 'error' && false; \
    timeout 5 sh -euc "until cat /tmp/smtp-sink/*; do sleep 0.1; done"; \
    grep -q 'Subject: Test' /tmp/smtp-sink/*; \
    rm -fr /tmp/smtp-sink
ONBUILD USER 0:0


FROM busybox:${BUSYBOX_VERSION:-1.34} AS busybox
COPY --from=busybox-tests /usr/local/bin/smtp-sink /usr/local/bin/tini /usr/local/bin/
USER 65534:65534
ENTRYPOINT [ "tini", "--", "smtp-sink" ]
CMD [ "-v", "0.0.0.0:1025" , "128" ]


FROM scratch AS distroless
COPY --from=busybox-tests /usr/local/bin/smtp-sink /usr/local/bin/tini /usr/local/bin/
USER 65534:65534
ENTRYPOINT [ "tini", "--", "smtp-sink" ]
CMD [ "-v", "0.0.0.0:1025" , "128" ]
