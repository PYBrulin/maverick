#!/bin/bash

# Set defaults, can be overriden in /srv/maverick/config/mavlink/mavlink-<instance>.service.conf
PROXY_PROVIDER=mavlink-router
ENABLE=true
SCREEN_NAME=mavlink-$1
MAVPROXY_PORT=/dev/ttyUSB0
MAVPROXY_BAUD=115200
MAVPROXY_ARGS="--out=udpin:0.0.0.0:14561 --out=tcpin:0.0.0.0:5761"
[ ! -r /srv/maverick/config/mavlink/mavlink-$1.service.conf ] || . /srv/maverick/config/mavlink/mavlink-$1.service.conf

if [ "$ENABLE" == "false" ]; then
    echo "ENABLE flag is set to false, exiting"
    exit 0
fi

echo "Starting Maverick Mavlink provider ${PROXY_PROVIDER}"

# Start the configured mavlink provider
if [ $PROXY_PROVIDER == "mavlink-router" ]
then
    /srv/maverick/software/mavlink-router/usr/bin/mavlink-routerd -c /srv/maverick/config/mavlink/mavlink-router-$1.conf

elif [ $PROXY_PROVIDER == "mavproxy" ]
then
    /usr/bin/screen -c /srv/maverick/config/mavlink/mavproxy-$1.screen.conf -S $SCREEN_NAME -D -m /srv/maverick/software/python/bin/mavproxy.py --master $MAVPROXY_PORT --baud $MAVPROXY_BAUD $MAVPROXY_FLOW --state-basedir=/srv/maverick/var/log/mavlink-$1 $MAVPROXY_ARGS

elif [ $PROXY_PROVIDER == "cmavnode" ]
then
    /usr/bin/screen -c /srv/maverick/config/mavlink/cmavnode-$1.screen.conf -S $SCREEN_NAME -D -m /srv/maverick/software/cmavnode/bin/cmavnode -f /srv/maverick/config/mavlink/cmavnode-$1.conf -i -v

else
    echo "Error: mavlink provider '${PROXY_PROVIDER}' is not recognised"

fi
