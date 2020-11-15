#!/usr/bin/env bash
set -e

hass --script auth -c /config change_password gavin $HOME_ASSISTANT_PASSWORD_GAVIN

# This is a terrible solution to having the iOS/Auth configuration
# migrated through the deployments
#
# However until Home Assistant moves away from using JSON files for a database its
# the "best" I can think of right now.
#
if test -f /config/persistent-auth/auth; then
    jq -s '.[0] * .[1]' /config/.storage/auth /config/persistent-auth/auth > /config/.storage/auth
fi

# Similar to above the iOS configuration needs restored
if test -f /config/persistent-auth/core.config_entries; then
    jq -s '.[0] * .[1]' /config/.storage/core.config_entries /config/persistent-auth/core.config_entries > /config/.storage/core.config_entries
fi

hass --script check_config -c /config/

/etc/s6/init/init-stage1 $@
