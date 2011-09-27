#!/bin/bash
CACHE=$HOME/.freeipmi/sensor-reading-cache
NRPE_OK=0
NRPE_WARN=1
NRPE_CRITICAL=2
NRPE_UNKNOWN=3
NRPE_PREFIX="IPMI "
CACHE_OLD=0
CACHE_ALLOWED_AGE=1
OK_MATCH="[OK]"
WARN_MATCH="Predicted"
CRITICAL_MATCH="FAIL"
SENSOR="io.hdd1.fail"


# First make sure the cache actually exists
if [ ! -r $CACHE ]; then
	echo "${NRPE_PREFIX}CRITICAL: Could not read sensor cache: $CACHE"
	exit $NRPE_CRITICAL
fi

# Now check to see if it is old
FIND_MMIN=$(($CACHE_ALLOWED_AGE+1*-1))
if [ -z `find $CACHE -type f -mmin $FIND_MMIN` ]; then
	CACHE_OLD=1
	NRPE_PREFIX="${NRPE_PREFIX}[OLD READING]: "
fi

# Now check for our sensor
SENSOR_READING=`egrep "$SENSOR" $CACHE`
if [ -z "$SENSOR_READING" ]; then
	echo "${NRPE_PREFIX}CRITICAL: No sensor reading for '$SENSOR'"
	exit $NRPE_CRITICAL
fi

# Check for the worst conditions first, filtering down
if [ -n `egrep "$CRITICAL_MATCH" $SENSOR_READING` ]; then
	echo "${NRPE_PREFIX}CRITICAL: $SENSOR: $SENSOR_READING"
	exit $NRPE_CRITICAL
elif [ -n `egrep "$WARN_MATCH" $SENSOR_READING` ]; then
	# No match for critical, try WARN
	echo "${NRPE_PREFIX}WARNING: $SENSOR: $SENSOR_READING"
else
	# OK is a little special, if OK_MATCH is null then we assume because
	# we didn't match CRIT or WARN then we are OK. 
	# if OK_MATCH is not null then it must match
	if [ -z $OK_MATCH ]; then
		echo "${NRPE_PREFIX}OK: $SENSOR: $SENSOR_READING"
		exit $NRPE_OK
	elif [ -n `egrep "$OK_MATCH" $SENSOR_READING` ]; then
		echo "${NRPE_PREFIX}OK: $SENSOR: $SENSOR_READING"
		exit $NRPE_OK
	else
		echo "${NRPE_PREFIX}CRITICAL: $SENSOR: $SENSOR_READING"
		exit $NRPE_CRITICAL
	fi
fi

# If we get here the we have some faulty logic :(
echo "${NRPE_PREFIX}CRITICAL: $SENSOR: $SENSOR_READING"
exit $NRPE_CRITICAL
