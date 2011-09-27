#!/bin/bash
CACHE_DIR=/var/log/ipmi
HOST=$HOSTNAME
CACHE=$CACHE_DIR/sensor-reading-cache.$HOSTNAME
if [ ! -d $CACHE_DIR ]; then
	mkdir -p $CACHE_DIR
fi
echo "# Sensor cache last updated at: `date`" > $CACHE
#/usr/sbin/ipmi-sensors 2>&1 >> $CACHE
/usr/sbin/ipmi-sensors >> $CACHE
echo "# Sensor cache last updated at: `date`" >> $CACHE
chown -R nagios:nagios $CACHE_DIR
chmod 644 $CACHE