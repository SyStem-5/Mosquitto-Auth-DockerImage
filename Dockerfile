FROM alpine:3.8

ENV VERSION=1.6.3 \
    DOWNLOAD_SHA256=9ef5cc75f4fe31d7bf50654ddf4728ad9e1ae2e5609a4b42ecbbcb4a209ed17e \
    GPG_KEYS=A0D6EEA1DCAE49A635A3B2F0779B22DFB3E717B7

COPY Mosquitto-Auth-Plugin /build/auth-plugin

RUN set -x && \
    apk --no-cache add --virtual build-deps \
        build-base \
        cmake \
        gnupg \
        libressl-dev \
        util-linux-dev &&\
    apk --no-cache add postgresql-dev && \
    rm -rf /root/.cmake && \
    wget https://mosquitto.org/files/source/mosquitto-${VERSION}.tar.gz -O /tmp/mosq.tar.gz && \
    echo "$DOWNLOAD_SHA256  /tmp/mosq.tar.gz" | sha256sum -c - && \
    wget https://mosquitto.org/files/source/mosquitto-${VERSION}.tar.gz.asc -O /tmp/mosq.tar.gz.asc && \
    export GNUPGHOME="$(mktemp -d)" && \
    found=''; \
    for server in \
        ha.pool.sks-keyservers.net \
        hkp://keyserver.ubuntu.com:80 \
        hkp://p80.pool.sks-keyservers.net:80 \
        pgp.mit.edu \
    ; do \
        echo "Fetching GPG key $GPG_KEYS from $server"; \
        gpg --keyserver "$server" --keyserver-options timeout=10 --recv-keys "$GPG_KEYS" && found=yes && break; \
    done; \
    test -z "$found" && echo >&2 "error: failed to fetch GPG key $GPG_KEYS" && exit 1; \
    gpg --batch --verify /tmp/mosq.tar.gz.asc /tmp/mosq.tar.gz && \
    gpgconf --kill all && \
    rm -rf "$GNUPGHOME" /tmp/mosq.tar.gz.asc && \
    mkdir -p /build/mosq && \
    tar --strip=1 -xf /tmp/mosq.tar.gz -C /build/mosq && \
    rm /tmp/mosq.tar.gz && \
    make -C /build/mosq -j "$(nproc)" \
        WITH_ADNS=no \
        WITH_DOCS=no \
        WITH_MEMORY_TRACKING=no \
        WITH_SHARED_LIBRARIES=yes \
        WITH_SRV=no \
        WITH_STRIP=no \
        WITH_TLS_PSK=yes \
        WITH_WEBSOCKETS=no \
        prefix=/usr \
        install && \
    addgroup -S -g 8883 mosquitto 2>/dev/null && \
    adduser -S -u 8883 -D -H -h /var/empty -s /sbin/nologin -G mosquitto -g mosquitto mosquitto 2>/dev/null && \
    mkdir -p /mosquitto/config /mosquitto/data /mosquitto/log && \
    install -d /usr/sbin/ && \
    install -s -m755 /build/mosq/client/mosquitto_pub /usr/bin/mosquitto_pub && \
    install -s -m755 /build/mosq/client/mosquitto_rr /usr/bin/mosquitto_rr && \
    install -s -m755 /build/mosq/client/mosquitto_sub /usr/bin/mosquitto_sub && \
    install -s -m644 /build/mosq/lib/libmosquitto.so.1 /usr/lib/libmosquitto.so.1 && \
    install -s -m755 /build/mosq/src/mosquitto /usr/sbin/mosquitto && \
    install -s -m755 /build/mosq/src/mosquitto_passwd /usr/bin/mosquitto_passwd && \
    install -m644 /build/mosq/mosquitto.conf /mosquitto/config/mosquitto.conf && \
    chown -R mosquitto:mosquitto /mosquitto && \
    echo Installing Auth-plugin && \
    printf "BACKEND_CDB?=no\n\
        BACKEND_MYSQL?=no\n\
        BACKEND_SQLITE?=no\n\
        BACKEND_REDIS?=no\n\
        BACKEND_POSTGRES?=yes\n\
        BACKEND_LDAP?=no\n\
        BACKEND_HTTP?=no\n\
        BACKEND_JWT?=no\n\
        BACKEND_MONGO?=no\n\
        BACKEND_FILES?=no\n\
        BACKEND_MEMCACHED?= no\n\
        MOSQUITTO_SRC=/build/mosq\n\
        OPENSSLDIR=/usr/\n\
        SUPPORT_DJANGO_HASHERS?=no"\
        > /build/auth-plugin/config.mk &&\
    make -C /build/auth-plugin -j "$(nproc)" && \
    mv /build/auth-plugin/auth-plug.so /mosquitto/config/ && \
    apk del build-deps && \
    rm -rf /build

VOLUME ["/mosquitto/data", "/mosquitto/log"]

# Set up the entry point script and default command
COPY docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/usr/sbin/mosquitto", "-c", "/mosquitto/config/mosquitto.conf"]
