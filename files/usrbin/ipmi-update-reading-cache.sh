#!/bin/bash
CACHE_DIR=$HOME/.freeipmi
CACHE=$CACHE_DIR/sensor-reading-cache
if [ ! -d $CACHE_DIR ]; then
	# Build SDR list
	ipmi-sensors 
fi
ipmi-sensors > $CACHE