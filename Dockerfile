ARG BUSYBOX_VERSION
ARG DEBIAN_VERSION

# hadolint ignore=DL3029
FROM --platform=${BUILDPLATFORM:-linux/amd64} debian:${DEBIAN_VERSION:?} AS gnupg-wget
SHELL [ "/bin/bash", "-o", "errexit", "-o", "nounset" , "-o", "pipefail", "-o", "posix", "-o", "xtrace", "-c" ]
# hadolint ignore=DL3008
RUN apt-get update; \
    apt-get install --assume-yes --no-install-recommends \
    ca-certificates \
    gnupg \
    wget \
    ; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*
USER 65534:65534
ONBUILD USER 0:0



FROM gnupg-wget AS postfix-source
SHELL [ "/bin/bash", "-o", "errexit", "-o", "nounset" , "-o", "pipefail", "-o", "posix", "-o", "xtrace", "-c" ]
WORKDIR /postfix
ARG POSTFIX_VERSION
ENV POSTFIX_VERSION=${POSTFIX_VERSION:?} \
    POSTFIX_KEY_FINGERPRINT=622C7C012254C186677469C50C0B590E80CA15A7
RUN GNUPGHOME=$(mktemp -d); \
    GNUPGHOME="${GNUPGHOME:?}" gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "${POSTFIX_KEY_FINGERPRINT:?}"; \
    printf "%s:6:\n" "${POSTFIX_KEY_FINGERPRINT:?}" | GNUPGHOME="${GNUPGHOME:?}" gpg --import-ownertrust; \
    wget --hsts-file=/dev/null --quiet "https://de.postfix.org/ftpmirror/official/postfix-${POSTFIX_VERSION:?}.tar.gz.gpg2"; \
    wget --hsts-file=/dev/null --quiet "https://de.postfix.org/ftpmirror/official/postfix-${POSTFIX_VERSION:?}.tar.gz"; \
    GNUPGHOME="${GNUPGHOME:?}" gpg --batch --verify "postfix-${POSTFIX_VERSION:?}.tar.gz.gpg2" "postfix-${POSTFIX_VERSION:?}.tar.gz"; \
    tar --no-same-owner --no-same-permissions --strip-components 1 -xzf "postfix-${POSTFIX_VERSION:?}.tar.gz"; \
    rm -fr "postfix-${POSTFIX_VERSION:?}.tar.gz" "postfix-${POSTFIX_VERSION:?}.tar.gz.gpg2" "${GNUPGHOME:?}"
USER 65534:65534
ONBUILD USER 0:0



FROM gnupg-wget AS tini-source
SHELL [ "/bin/bash", "-o", "errexit", "-o", "nounset" , "-o", "pipefail", "-o", "posix", "-o", "xtrace", "-c" ]
WORKDIR /tini
ARG TINI_VERSION
ENV TINI_VERSION=${TINI_VERSION:?}
RUN wget --hsts-file=/dev/null --quiet "https://github.com/krallin/tini/archive/refs/tags/v${TINI_VERSION:?}.tar.gz"; \
    tar --no-same-owner --no-same-permissions --strip-components 1 -xzf "v${TINI_VERSION:?}.tar.gz"; \
    rm -fr "v${TINI_VERSION:?}.tar.gz"
USER 65534:65534
ONBUILD USER 0:0



FROM debian:${DEBIAN_VERSION:?} AS build-dependencies
SHELL [ "/bin/bash", "-o", "errexit", "-o", "nounset" , "-o", "pipefail", "-o", "posix", "-o", "xtrace", "-c" ]
# hadolint ignore=DL3008
RUN apt-get update; \
    apt-get install --assume-yes --no-install-recommends \
    cmake \
    curl \
    libc6-dev \
    make \
    musl-tools \
    netcat-traditional \
    ; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*
USER 65534:65534
ONBUILD USER 0:0



FROM build-dependencies AS tini-binary
SHELL [ "/bin/bash", "-o", "errexit", "-o", "nounset" , "-o", "pipefail", "-o", "posix", "-o", "xtrace", "-c" ]
COPY --from=tini-source /tini /tini
WORKDIR /tini
RUN export CC="musl-gcc"; \
    export CFLAGS="-static -s -DPR_SET_CHILD_SUBREAPER=36 -DPR_GET_CHILD_SUBREAPER=37"; \
    cmake "${PWD:?}"; \
    make; \
    install -Dm 755 tini-static /usr/local/sbin/tini
USER 65534:65534
ONBUILD USER 0:0



FROM build-dependencies AS postfix-binaries
SHELL [ "/bin/bash", "-o", "errexit", "-o", "nounset" , "-o", "pipefail", "-o", "posix", "-o", "xtrace", "-c" ]
COPY --from=postfix-source /postfix /postfix
WORKDIR /postfix
RUN MUSL_INCLUDE_DIR="$(find /usr/include -maxdepth 1 -type d -name '*-linux-musl*')"; \
    MUSL_LIB_DIR="$(find /usr/lib -maxdepth 1 -type d -name '*-linux-musl*')"; \
    GNU_LIB_DIR="$(find /usr/lib -maxdepth 1 -type d -name '*-linux-gnu*')"; \
    mkdir -p "${MUSL_INCLUDE_DIR:?}/linux"; \
    ln -s /usr/include/linux/version.h "${MUSL_INCLUDE_DIR:?}/linux/version.h"; \
    ln -s "${GNU_LIB_DIR:?}/libnsl.a" "${MUSL_LIB_DIR:?}/libnsl.a"; \
    CC="musl-gcc -static -s"; \
    CCARGS="-DNO_DB -DNO_NIS -DNO_PCRE"; \
    DIRS="src/util src/global src/smtpstone"; \
    OPT="-Ofast"; \
    make --silent makefiles CC="${CC:?}" CCARGS="${CCARGS:?}" DIRS="${DIRS:?}" OPT="${OPT:?}"; \
    make --silent DIRS="${DIRS:?}"; \
    install -Dm 755 bin/smtp-sink /usr/local/bin/smtp-sink
USER 65534:65534
ONBUILD USER 0:0



FROM build-dependencies as debian-tests
SHELL [ "/bin/bash", "-o", "errexit", "-o", "nounset" , "-o", "pipefail", "-o", "posix", "-o", "xtrace", "-c" ]
COPY --from=postfix-binaries /usr/local/bin/smtp-sink /usr/local/bin/smtp-sink
COPY --from=tini-binary /usr/local/sbin/tini /usr/local/sbin/tini
USER 65534:65534
# 1. start smtp-sink in a subprocess
# 2. wait until the port is open (up to a 1 second)
# 3. send a test email
RUN (tini -s -- smtp-sink 0.0.0.0:1025 128 &); \
    for _ in seq 1 10; do nc -vz 127.0.0.1 1025 && break; sleep 0.1; done; \
    printf 'From: sender@localhost\nTo: recipient@localhost\nSubject: Test\n\nTest' | \
      curl --silent --show-error --url 'smtp://127.0.0.1:1025' --mail-from 'sender@localhost' --mail-rcpt 'recipient@localhost' --upload-file -
# same as the first test, but this time the test email gets dumped to a file
RUN (tini -s -- smtp-sink -d "/tmp/smtp-sink/%M" 0.0.0.0:1025 128 &); \
    for _ in seq 1 10; do nc -vz 127.0.0.1 1025 && break; sleep 0.1; done; \
    printf 'From: sender@localhost\nTo: recipient@localhost\nSubject: Test\n\nTest' | \
      curl --silent --show-error --url 'smtp://127.0.0.1:1025' --mail-from 'sender@localhost' --mail-rcpt 'recipient@localhost' --upload-file -; \
    grep -lr 'Subject: Test' /tmp/smtp-sink | xargs -t cat; \
    rm -fr /tmp/smtp-sink
ONBUILD USER 0:0



FROM busybox:${BUSYBOX_VERSION:?} AS busybox-tests
SHELL [ "/bin/ash", "-o", "errexit", "-o", "nounset" , "-o", "pipefail", "-o", "xtrace", "-c" ]
COPY --from=debian-tests /usr/local/sbin/tini /usr/local/sbin/tini
COPY --from=debian-tests /usr/local/bin/smtp-sink /usr/local/bin/smtp-sink
USER 65534:65534
# 1. start smtp-sink in a subprocess
# 2. wait until the port is open (up to a 1 second)
# 3. send a test email
RUN (tini -s -- smtp-sink 0.0.0.0:1025 128 &); \
    for _ in seq 1 10; do nc -vz 127.0.0.1 1025 && break; sleep 0.1; done; \
    printf 'From: sender@localhost\nTo: recipient@localhost\nSubject: Test\n\nTest' | sendmail -f sender@localhost -S 127.0.0.1:1025 -t -v
# same as the first test, but this time the test email gets dumped to a file
RUN (tini -s -- smtp-sink -d "/tmp/smtp-sink/%M" 0.0.0.0:1025 128 &); \
    for _ in seq 1 10; do nc -vz 127.0.0.1 1025 && break; sleep 0.1; done; \
    printf 'From: sender@localhost\nTo: recipient@localhost\nSubject: Test\n\nTest' | sendmail -f sender@localhost -S 127.0.0.1:1025 -t -v; \
    grep -lr 'Subject: Test' /tmp/smtp-sink | xargs -t cat; \
    rm -fr /tmp/smtp-sink
ONBUILD USER 0:0



FROM busybox:${BUSYBOX_VERSION:?} AS busybox
SHELL [ "/bin/ash", "-o", "errexit", "-o", "nounset" , "-o", "pipefail", "-o", "xtrace", "-c" ]
COPY --from=busybox-tests /usr/local/sbin/tini /usr/local/sbin/tini
COPY --from=busybox-tests /usr/local/bin/smtp-sink /usr/local/bin/smtp-sink
USER 65534:65534
ENTRYPOINT [ "tini", "--", "smtp-sink" ]
CMD [ "0.0.0.0:1025" , "128" ]



FROM scratch AS distroless
COPY --from=busybox-tests /usr/local/sbin/tini /usr/local/sbin/tini
COPY --from=busybox-tests /usr/local/bin/smtp-sink /usr/local/bin/smtp-sink
USER 65534:65534
ENTRYPOINT [ "tini", "--", "smtp-sink" ]
CMD [ "0.0.0.0:1025" , "128" ]
