FROM alpine:3.14.2 AS build-stage
SHELL [ "/bin/ash", "-o", "errexit", "-o", "nounset" , "-o", "pipefail", "-o", "xtrace", "-c" ]

RUN apk add --no-cache \
    ca-certificates \
    gnupg \
    tar \
    wget \
    ;

ENV POSTFIX_KEY_FINGERPRINT=622C7C012254C186677469C50C0B590E80CA15A7
RUN gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "${POSTFIX_KEY_FINGERPRINT:?}"; \
    printf "%s:6:\n" "${POSTFIX_KEY_FINGERPRINT:?}" | gpg --import-ownertrust

ENV TINI_KEY_FINGERPRINT=595E85A6B1B4779EA4DAAEC70B588DFF0527A9B7
RUN gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "${TINI_KEY_FINGERPRINT:?}"; \
    printf "%s:6:\n" "${TINI_KEY_FINGERPRINT:?}" | gpg --import-ownertrust

ENV TINI_VERSION=0.19.0
RUN wget --quiet "https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini-static-amd64.asc"; \
    wget --quiet "https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini-static-amd64"; \
    gpg --batch --verify tini-static-amd64.asc tini-static-amd64; \
    install -Dm 755 tini-static-amd64 /usr/local/sbin/tini; \
    install -Dm 755 tini-static-amd64 /rootfs/usr/local/sbin/tini

ENV POSTFIX_VERSION=3.6.2
RUN wget --quiet "https://de.postfix.org/ftpmirror/official/postfix-${POSTFIX_VERSION:?}.tar.gz.gpg2"; \
    wget --quiet "https://de.postfix.org/ftpmirror/official/postfix-${POSTFIX_VERSION:?}.tar.gz"; \
    gpg --batch --verify "postfix-${POSTFIX_VERSION:?}.tar.gz.gpg2" "postfix-${POSTFIX_VERSION:?}.tar.gz"; \
    tar xzf "postfix-${POSTFIX_VERSION:?}.tar.gz"

RUN apk add --no-cache \
    gcc \
    linux-headers \
    make \
    musl-dev \
    ;

RUN CC="gcc -static -s"; \
    CCARGS="-DNO_DB -DNO_NIS"; \
    DIRS="src/util src/global src/smtpstone"; \
    OPT="-Ofast"; \
    make --directory="postfix-${POSTFIX_VERSION:?}" --silent makefiles CC="${CC:?}" CCARGS="${CCARGS:?}" DIRS="${DIRS:?}" OPT="${OPT:?}"; \
    make --directory="postfix-${POSTFIX_VERSION:?}" --silent DIRS="${DIRS:?}"; \
    install -Dm 755 "postfix-${POSTFIX_VERSION:?}/bin/smtp-sink" /usr/local/bin/smtp-sink

# Tests
USER 65534:65534
# Assert that the binary does depend on any shared libraries.
RUN ldd /usr/local/bin/smtp-sink || true
# Assert that the binary is smaller than 160 kB.
RUN test "160000" -gt "$(stat -c"%s" /usr/local/bin/smtp-sink)"
# 1. start smtp-sink in a subprocess
# 2. wait until the port is open (up to a 1 second)
# 3. send a test email
RUN (tini -s -- smtp-sink 0.0.0.0:1025 128 &); \
    for _ in seq 1 10; do nc -vz 127.0.0.1 1025 && break; sleep 0.1; done; \
    printf 'From: sender@localhost\nTo: recipient@localhost\nSubject: Test\n\nTest' | sendmail -f sender@localhost -S 127.0.0.1:1025 -t -v
# same as above, but this time the test email gets dumped to a file
RUN (tini -s -- smtp-sink -d "/tmp/smtp-sink/%M" 0.0.0.0:1025 128 &); \
    for _ in seq 1 10; do nc -vz 127.0.0.1 1025 && break; sleep 0.1; done; \
    printf 'From: sender@localhost\nTo: recipient@localhost\nSubject: Test\n\nTest' | sendmail -f sender@localhost -S 127.0.0.1:1025 -t -v; \
    grep -lr 'Subject: Test' /tmp/smtp-sink | xargs -t cat

USER 0:0
RUN install -Dm 755 /usr/local/bin/smtp-sink /rootfs/usr/local/bin/smtp-sink

USER 65534:65534
ENTRYPOINT [ "tini", "--", "smtp-sink" ]
CMD [ "-c", "-v", "0.0.0.0:1025" , "128" ]

FROM alpine:3.14.2 AS alpine
COPY --from=build-stage /rootfs /
USER 65534:65534
ENTRYPOINT [ "tini", "--", "smtp-sink" ]
CMD [ "-c", "-v", "0.0.0.0:1025" , "128" ]

FROM busybox:1.33.1-uclibc AS busybox
COPY --from=build-stage /rootfs /
USER 65534:65534
ENTRYPOINT [ "tini", "--", "smtp-sink" ]
CMD [ "-c", "-v", "0.0.0.0:1025" , "128" ]

FROM scratch AS distroless
COPY --from=build-stage /rootfs /
USER 65534:65534
ENTRYPOINT [ "tini", "--", "smtp-sink" ]
CMD [ "-c", "-v", "0.0.0.0:1025" , "128" ]
