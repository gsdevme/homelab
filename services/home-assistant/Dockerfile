ARG HOME_ASSISTANT_VERSION=latest

FROM homeassistant/home-assistant:$HOME_ASSISTANT_VERSION

ENV MQTT_HOST=mqtt.home.gsdev.me
ENV DSM_HOST=nas.home.gsdev.me
ENV TZ=London/Europe

COPY sensors/*.yaml /config/sensors/
COPY binary-sensors/*.yaml /config/binary-sensors/
COPY switches/*.yaml /config/switches/
COPY storage/* /config/bootstrap/
COPY *.yaml /config/
COPY entrypoint.sh /bin/entrypoint.sh

RUN chmod +x /bin/entrypoint.sh && \
    apk --no-cache add apache2-utils jq && \
    mkdir -p /config/www


RUN cd /config/www/ && \
    wget https://github.com/denysdovhan/vacuum-card/releases/download/v1.12.0/vacuum-card.js

# Assert the configuration is ok before finalising the image
RUN hass --script check_config -c /config/

ENTRYPOINT ["/bin/entrypoint.sh"]
