#!/usr/bin/env bash

hass --script auth -c /config change_password gavin $HOME_ASSISTANT_PASSWORD_GAVIN

/etc/s6/init/init-stage1 $@
