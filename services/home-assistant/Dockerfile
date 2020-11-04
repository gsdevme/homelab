ARG HOME_ASSISTANT_VERSION=latest

FROM homeassistant/home-assistant:$HOME_ASSISTANT_VERSION

ENV TZ=Europe/London
ENV MQTT_HOST=172.16.16.180

COPY sensors/*.yaml /config/sensors/
COPY *.yaml /config/
COPY storage/* /config/.storage/

# Assert the configuration is ok before finalising the image
RUN hass --script check_config -c /config/
