ARG HOME_ASSISTANT_VERSION=latest

FROM homeassistant/home-assistant:$HOME_ASSISTANT_VERSION

COPY sensors/*.yaml /config/sensors/
COPY binary-sensors/*.yaml /config/binary-sensors/
COPY switches/*.yaml /config/switches/
COPY storage/* /config/.storage/
COPY *.yaml /config/
COPY entrypoint.sh /bin/entrypoint.sh

RUN chmod +x /bin/entrypoint.sh && \
    apk --no-cache add apache2-utils jq && \
    mkdir -p /config/www

RUN curl https://github.com/denysdovhan/vacuum-card/releases/download/v1.12.0/vacuum-card.js -o /config/www/vacuum-card.js

# Assert the configuration is ok before finalising the image
RUN hass --script check_config -c /config/

ENTRYPOINT ["/bin/entrypoint.sh"]
