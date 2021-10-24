FROM debian:unstable-slim AS build-stage
SHELL [ "/bin/bash", "-o", "errexit", "-o", "nounset" , "-o", "pipefail", "-o", "posix", "-o", "xtrace", "-c" ]

RUN apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get upgrade --assume-yes; \
    DEBIAN_FRONTEND=noninteractive apt-get install --assume-yes --no-install-recommends \
    ca-certificates \
    gnupg \
    wget \
    gcc \
    libc6-dev \
    m4 \
    make \
    ;

ENV POSTFIX_VERSION=3.6.2 \
    POSTFIX_KEY_FINGERPRINT=622C7C012254C186677469C50C0B590E80CA15A7

RUN wget --quiet "https://de.postfix.org/ftpmirror/official/postfix-${POSTFIX_VERSION:?}.tar.gz.gpg2"; \
    gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "${POSTFIX_KEY_FINGERPRINT:?}"; \
    printf "%s:6:\n" "${POSTFIX_KEY_FINGERPRINT:?}" | gpg --import-ownertrust; \
    wget --quiet "https://de.postfix.org/ftpmirror/official/postfix-${POSTFIX_VERSION:?}.tar.gz"; \
    gpg --batch --verify "postfix-${POSTFIX_VERSION:?}.tar.gz.gpg2" "postfix-${POSTFIX_VERSION:?}.tar.gz"; \
    tar xzf "postfix-${POSTFIX_VERSION:?}.tar.gz"

RUN CC="gcc -static -static-libgcc -static-libstdc++ -D_FORTIFY_SOURCE=2 -fPIE -fstack-protector-strong -pie -Wl,-z,relro,-z,now"; \
    make --directory="postfix-${POSTFIX_VERSION:?}" --silent makefiles CC="${CC:?}" CCARGS="-DNO_DB -DNO_NIS -DNO_PCRE" OPT="-O3"; \
    make --directory="postfix-${POSTFIX_VERSION:?}" --silent; \
    install -Dm 755 "postfix-${POSTFIX_VERSION:?}/bin/smtp-sink" /usr/local/bin/smtp-sink; \
    install -Dm 755 "postfix-${POSTFIX_VERSION:?}/bin/smtp-sink" /rootfs/usr/local/bin/smtp-sink

# Apparently smtp-sink ignores stop signals when it has the PID 1.
ENV TINI_VERSION=0.19.0 \
    TINI_KEY_FINGERPRINT=595E85A6B1B4779EA4DAAEC70B588DFF0527A9B7
RUN wget --quiet "https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini-static-amd64.asc"; \
    gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "${TINI_KEY_FINGERPRINT:?}"; \
    printf "%s:6:\n" "${TINI_KEY_FINGERPRINT:?}" | gpg --import-ownertrust; \
    wget --quiet "https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini-static-amd64"; \
    gpg --batch --verify tini-static-amd64.asc tini-static-amd64; \
    install -Dm 755 tini-static-amd64 /usr/local/sbin/tini; \
    install -Dm 755 tini-static-amd64 /rootfs/usr/local/sbin/tini

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