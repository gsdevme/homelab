ARG HOME_ASSISTANT_VERSION=stable

FROM homeassistant/home-assistant:$HOME_ASSISTANT_VERSION

ENV MQTT_HOST=zigbee2mqtt.home.gsdev.me
ENV DSM_HOST=nas.home.gsdev.me
ENV TZ=London/Europe

COPY sensors/*.yaml /config/sensors/
COPY binary-sensors/*.yaml /config/binary-sensors/
COPY switches/*.yaml /config/switches/
COPY automations/*.yaml /config/automations/
COPY storage/* /config/bootstrap/
COPY *.yaml /config/
COPY entrypoint.sh /bin/entrypoint.sh

RUN chmod +x /bin/entrypoint.sh && \
    apk --no-cache add apache2-utils jq tzdata && \
    echo "Europe/London" >  /etc/timezone && \
    mkdir -p /config/www

RUN cd /config/www/ && \
    wget https://github.com/denysdovhan/vacuum-card/releases/download/v1.12.0/vacuum-card.js && \
    wget https://raw.githubusercontent.com/thomasloven/lovelace-layout-card/16/layout-card.js && \
    wget https://raw.githubusercontent.com/robmarkoski/ha-clockwork-card/v0.1.2/clockwork-card.js && \
    wget https://raw.githubusercontent.com/thomasloven/lovelace-auto-entities/master/auto-entities.js

# Assert the configuration is ok before finalising the image
RUN hass --script check_config -c /config/

ENTRYPOINT ["/bin/entrypoint.sh"]
