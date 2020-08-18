#!/bin/sh
set -e

echo "MMTT Host: ${MQTT_HOST}"
echo "Hue Host: ${HUE_HOST}"

echo "{\"hue\": {\"host\": \"${HUE_HOST}\",\"username\": \"${HUE_AUTH}\"},\"mqtt\": \"mqtt://${MQTT_HOST}\"}" > /srv/app/mqtt-hue/config.json

exec "$@"
