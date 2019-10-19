FROM debian:9-slim

ENV VERSION=1.6.3 \
    DOWNLOAD_SHA256=9ef5cc75f4fe31d7bf50654ddf4728ad9e1ae2e5609a4b42ecbbcb4a209ed17e \
    GPG_KEYS=A0D6EEA1DCAE49A635A3B2F0779B22DFB3E717B7

ENV PLUGIN_VERSION=0.6.1 \
    PLUGIN_SHA256=12dae156958b623343f67140ff9d1d1715e25a1b95ab25ff18ac4e39a83cb1a7 \
    GO_VERSION=1.12.7

RUN apt-get update -y --no-install-recommends \
    && export BUILD_DEPS="wget make gpg build-essential git" \
    && apt-get install -y $BUILD_DEPS libwrap0-dev libssl-dev libc-ares-dev uuid-dev libpq-dev \
    && rm -rf /var/lib/apt/lists/* \
    && wget https://dl.google.com/go/go${GO_VERSION}.linux-amd64.tar.gz \
    && tar -xvf go${GO_VERSION}.linux-amd64.tar.gz \
    && rm go${GO_VERSION}.linux-amd64.tar.gz \
    && mv go /usr/local \
    && export GOROOT=/usr/local/go && export GOPATH=/build && export PATH=$GOPATH/bin:$GOROOT/bin:$PATH \
    && rm -rf /root/.cmake \
    && wget https://mosquitto.org/files/source/mosquitto-${VERSION}.tar.gz -O /tmp/mosq.tar.gz \
    && echo "$DOWNLOAD_SHA256  /tmp/mosq.tar.gz" | sha256sum -c - \
    && wget https://mosquitto.org/files/source/mosquitto-${VERSION}.tar.gz.asc -O /tmp/mosq.tar.gz.asc \
    && export GNUPGHOME="$(mktemp -d)" \
    && found=''; \
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
    gpg --batch --verify /tmp/mosq.tar.gz.asc /tmp/mosq.tar.gz \
    && gpgconf --kill all \
    && rm -rf "$GNUPGHOME" /tmp/mosq.tar.gz.asc \
    && mkdir -p /build/mosq \
    && tar --strip=1 -xf /tmp/mosq.tar.gz -C /build/mosq \
    && rm /tmp/mosq.tar.gz \
    && make -C /build/mosq -j "$(nproc)" \
        WITH_ADNS=no \
        WITH_DOCS=no \
        WITH_MEMORY_TRACKING=no \
        WITH_SHARED_LIBRARIES=yes \
        WITH_SRV=no \
        WITH_STRIP=no \
        WITH_TLS_PSK=yes \
        WITH_WEBSOCKETS=no \
        prefix=/usr \
        install \
    && addgroup --system --gid 8883 mosquitto \
    && adduser --system --uid 8883 --disabled-password --disabled-login --no-create-home --group mosquitto --gecos mosquitto \
    && mkdir -p /mosquitto/config /mosquitto/data /mosquitto/log \
    && install -d /usr/sbin/ \
    && install -s -m755 /build/mosq/client/mosquitto_pub /usr/bin/mosquitto_pub \
    && install -s -m755 /build/mosq/client/mosquitto_rr /usr/bin/mosquitto_rr \
    && install -s -m755 /build/mosq/client/mosquitto_sub /usr/bin/mosquitto_sub \
    && install -s -m644 /build/mosq/lib/libmosquitto.so.1 /usr/lib/libmosquitto.so.1 \
    && install -s -m755 /build/mosq/src/mosquitto /usr/sbin/mosquitto \
    && install -s -m755 /build/mosq/src/mosquitto_passwd /usr/bin/mosquitto_passwd \
    && install -m644 /build/mosq/mosquitto.conf /mosquitto/config/mosquitto.conf \
    && chown -R mosquitto:mosquitto /mosquitto \
    && echo "Downloading & Building Auth-plugin $PLUGIN_VERSION..." \
    && wget https://github.com/iegomez/mosquitto-go-auth/archive/${PLUGIN_VERSION}.tar.gz -O /tmp/go-auth.tar.gz \
    && echo "Comparing hashes..." \
    && echo "$PLUGIN_SHA256  /tmp/go-auth.tar.gz" | sha256sum -c - \
    && mkdir -p /build/go-auth \
    && tar --strip=1 -xf /tmp/go-auth.tar.gz -C /build/go-auth \
    && rm /tmp/go-auth.tar.gz \
    && export PATH=$PATH:/usr/local/go/bin && export CGO_CFLAGS="-I/usr/local/include -fPIC" && export CGO_LDFLAGS="-shared" \
    && make -C /build/go-auth \
    && install -s -m644 /build/go-auth/go-auth.so /mosquitto/config/go-auth.so \
    && apt-get -y remove $BUILD_DEPS \
    && apt-get -y clean \
    && apt-get -y autoremove \
    && rm -rf /build


COPY default_mosquitto.conf /mosquitto/config/mosquitto.conf
COPY docker-entrypoint.sh /

VOLUME ["/mosquitto/data", "/mosquitto/log"]

# Set up the entry point script and default command
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/usr/sbin/mosquitto", "-c", "/mosquitto/config/mosquitto.conf"]
