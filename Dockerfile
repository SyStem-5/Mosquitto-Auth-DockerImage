FROM debian:8.11-slim

COPY compile_config /tmp/compile_config

COPY config /mqtt/config

COPY docker-entrypoint.sh /bin/

# This requires that the authentication/authorization plugin folder is placed in the same dir as this Dockerfile
COPY mosquitto-auth-plugin /tmp/mosquitto-auth-plugin

RUN apt-get update \
	&& apt-get install -y wget make libpq-dev libc-ares-dev libcurl4-openssl-dev uuid-dev libc6-dev gcc build-essential g++ \
	&& wget -q http://mosquitto.org/files/source/mosquitto-1.5.tar.gz -O /tmp/mosquitto-1.5.tar.gz \
	&& cd /tmp/ \
	&& tar zxvf mosquitto-1.5.tar.gz \
	&& rm -f mosquitto-1.5.tar.gz \
	&& cd ./mosquitto-1.5 \
	&& mv /tmp/compile_config/mqtt_config.mk ./config.mk \
	&& make install \
	&& ldconfig /usr/lib/x86_64-linux-gnu/ \
	&& cd ../mosquitto-auth-plugin \
	# && git clone https://github.com/jpmens/mosquitto-auth-plug.git \
	# && cd mosquitto-auth-plugin \
	&& mv /tmp/compile_config/auth_config.mk ./config.mk \
	&& make \
	&& mkdir -p /mqtt/config /mqtt/data /mqtt/log \
	&& cp auth-plug.so /mqtt/config/ \
	&& rm -r /tmp/* \
	&& apt -y remove gcc build-essential g++ make wget \
	&& apt-get clean autoclean \
	&& apt-get autoremove --yes\
	&& rm -rf /var/lib/{apt,dpkg,cache,log}/ \
	&& adduser --system --disabled-password --disabled-login mosquitto \
	&& groupadd mosquitto \
	&& usermod -g mosquitto mosquitto \
	&& chown -R mosquitto:mosquitto /mqtt \
	&& chmod +x /bin/docker-entrypoint.sh

#RUN chown -R mosquitto:mosquitto /mqtt
VOLUME ["/mqtt/config", "/mqtt/data", "/mqtt/log"]

EXPOSE 8883


#RUN chmod +x /bin/docker-entrypoint.sh

ENTRYPOINT ["/bin/docker-entrypoint.sh"]
CMD ["/usr/local/sbin/mosquitto", "-c", "/mqtt/config/mosquitto.conf"]
