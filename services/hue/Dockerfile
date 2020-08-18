FROM node:lts

ENV MQTT_HOST="127.0.0.1"
ENV HUE_HOST="172.0.0.1"
ENV HUE_AUTH="password"

COPY docker-entrypoint.sh /usr/bin/

RUN chmod +x /usr/bin/docker-entrypoint.sh \
    && apt-get update && apt-get install git -y \
    && mkdir -p /srv/app/ && cd /srv/app/ \
    && git clone https://github.com/Darksecond/mqtt-hue.git \
    && cd mqtt-hue \
    && rm -rf config.json \
    && npm install \
    && npm install forever

WORKDIR /srv/app/mqtt-hue

ENTRYPOINT ["/bin/sh", "/usr/bin/docker-entrypoint.sh"]

CMD ["node", "server.js", "2>&1"]
