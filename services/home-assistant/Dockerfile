ARG HOME_ASSISTANT_VERSION=latest

FROM homeassistant/home-assistant:$HOME_ASSISTANT_VERSION

COPY sensors/*.yaml /config/sensors/
COPY binary-sensors/*.yaml /config/binary-sensors/
COPY switches/*.yaml /config/switches/
COPY storage/* /config/.storage/
COPY *.yaml /config/
COPY entrypoint.sh /bin/entrypoint.sh

RUN chmod +x /bin/entrypoint.sh && \
    apk --no-cache add apache2-utils

# Assert the configuration is ok before finalising the image
RUN hass --script check_config -c /config/

ENTRYPOINT ["/bin/entrypoint.sh"]
