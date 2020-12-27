#!/usr/bin/env bash
set -e

if [ ! -f /config/.storage/onboarding ]; then
    [ ! -d "/config/.storage/" ] && mkdir -p /config/.storage/

    echo "First boot of .storage"
    cp -R /config/bootstrap/* /config/.storage/.
fi

hass --script auth -c /config change_password gavin $HOME_ASSISTANT_PASSWORD_GAVIN
hass --script auth -c /config change_password ceilidh HOME_ASSISTANT_PASSWORD_CEILIDH

hass --script check_config -c /config/

/etc/s6/init/init-stage1 $@
