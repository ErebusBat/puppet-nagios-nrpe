#!/bin/bash 
CACHE=$HOME/.freeipmi/sensor-reading-cache
MATCHED=127
NRPE_OK=0
NRPE_WARN=1
NRPE_CRITICAL=2
NRPE_UNKNOWN=3
NRPE_PREFIX="IPMI "
CACHE_OLD=0
CACHE_ALLOWED_AGE=1
OK_MATCH=
WARN_MATCH="warn"
CRITICAL_MATCH="\sAsserted"
SENSOR="io.hdd1.fail"

# Returns 0 if match
function grep_string() {
	STR=$1
	CHECK=$2
	echo $STR | egrep --ignore-case $CHECK > /dev/null
}

# Returns $MATCHED if match
function grep_and_set {
	STR=$1
	CHECK=$2
	UNMATCHED_RETURN_VALUE=$3
	RETURN_MESSAGE=$4
	grep_string "$STR" "$CHECK"
	if [ $? -eq 0 ]; then return $MATCHED; fi
	__c="Match not found"
	return $(($UNMATCHED_RETURN_VALUE+0))
}

# First make sure the cache actually exists
__c="Checking for sensor cache readability @ $CACHE"
if [ ! -r $CACHE ]; then
	echo "${NRPE_PREFIX}CRITICAL: Could not read sensor cache: $CACHE"
	exit $NRPE_CRITICAL
fi

# Now check to see if it is old
FIND_MMIN=$(($CACHE_ALLOWED_AGE+0))
__c="Checking if cache is old -min -$FIND_MMIN"
if [ -z `find $CACHE -type f -mmin -$FIND_MMIN` ]; then
	CACHE_OLD=1
	NRPE_PREFIX="${NRPE_PREFIX}[OLD READING]> "
fi

# Now check for our sensor
SENSOR_READING=`egrep "$SENSOR" $CACHE`
__c="Sensor reading: $SENSOR_READING"
if [ -z "$SENSOR_READING" ]; then
	echo "${NRPE_PREFIX}CRITICAL: No sensor reading for '$SENSOR'"
	exit $NRPE_CRITICAL
fi

# Check for the worst conditions first, filtering down
#if [ -n `egrep "$CRITICAL_MATCH" $SENSOR_READING` ]; then
__c="Check CRITICAL: $CRITICAL_MATCH"
grep_and_set "$SENSOR_READING" "$CRITICAL_MATCH" $NRPE_CRITICAL "${NRPE_PREFIX}CRITICAL: $SENSOR_READING"
if [ $? -eq $MATCHED ]; then
	echo $RETURN_MESSAGE
	exit $UNMATCHED_RETURN_VALUE
fi

# Warning
__c="Check WARN: $WARN_MATCH"
grep_and_set "$SENSOR_READING" "$WARN_MATCH" $NRPE_WARN "${NRPE_PREFIX}WARNING: $SENSOR_READING"
if [ $? -eq $MATCHED ]; then
	echo $RETURN_MESSAGE
	exit $UNMATCHED_RETURN_VALUE
fi

# OK is a little special, if OK_MATCH is null then we assume because
# we didn't match CRIT or WARN then we are OK. 
# if OK_MATCH is not null then it must match
if [ -z $OK_MATCH ]; then
	__c="OK Match is Null and not WARN or FAIL so assume OK"
	echo "${NRPE_PREFIX}OK: $SENSOR_READING"
	exit $NRPE_OK
else	
	__c="Check OK: $OK_MATCH"
	grep_and_set "$SENSOR_READING" "$OK_MATCH" $NRPE_OK "${NRPE_PREFIX}OK: $SENSOR_READING"
	if [ $? -eq $MATCHED ]; then
		echo $RETURN_MESSAGE
		exit $UNMATCHED_RETURN_VALUE
	fi
fi	

# If we get here the we have some faulty logic :(
__c="No matches found, UNKOWN status :("
echo "${NRPE_PREFIX}UNKNOWN: $SENSOR: $SENSOR_READING"
exit $NRPE_UNKNOWN
