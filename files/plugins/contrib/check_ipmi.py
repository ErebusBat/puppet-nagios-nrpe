#!/usr/bin/python

# See:
#  http://code.google.com/p/pni-toolbox/source/browse/trunk/Nagios/plugins/check_ipmi.py
#  http://blog.shadowgears.com/2010/07/nagios-ipmi-monitoring.html


# check_ipmi.py for ipmi querries in Nagios
# Copyright (C) 2010  Garrett McGrath

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

# This script will allow you to querry the status of one or more sensors connected to
# an IPMI board.  It utilizes and requires the FreeIPMI package as it utilizes the 'ipmi-sensors' command.
# To utilize this command you will need to have a sensor map for each type of hardware you wish to monitor.
# This sensor map can be retrieved by running the command: "impi-sensors -h <hostname> -u <username> -p <password>"
# This will dump a list similar to the following into your console:
# (this is a partial sensor list for a Sunfire X2200)
# 640: CPU 0 Temp (Temperature): 40.00 C (NA/95.00): [OK]
# 704: CPU 1 Temp (Temperature): 41.00 C (NA/95.00): [OK]
# 768: Ambient Temp0 (Temperature): 36.00 C (NA/75.00): [OK]
# 832: Ambient Temp1 (Temperature): 41.00 C (NA/75.00): [OK]
# 1632: CPU0 DIMM0 (Memory): [OK]
# 1680: CPU0 DIMM1 (Memory): [OK]
# 1728: CPU0 DIMM2 (Memory): [OK]
# 2400: POST Error (System Firmware): [Unknown]
# 2448: Eventlog (Event Logging Disabled): [OK]
# 2496: System Event (System Event): [OK]
# 2544: Critical INT (Critical Interrupt): [OK]
# 2592: Watchdog (Watchdog 2): [OK]


# Usage:
# check_ipmi -n <hostname> -u <ipmi username> -p <ipmi password> -s <comma seperated sensor ID list>
# You can include the optional arguement '-e' with a comma seperated list of expected values. (blanks default to looking for OK)
#  This is useful for instances where 'OK' is not the typical return statement, as nagios has no way to translate but will happily take error codes.

# import sys

from optparse import OptionParser
import os, sys, re
from commands import getoutput

_OK = 0
_NAGIOS_WARNING = 1
_NAGIOS_ERROR = 2
_MISSING_CHASSIS_EXPECTED = 3
_MISMATCHED_CHASSIS_EXPECTED = 4
_SENSOR_OUTPUT_WARNING  = 5
_SENSOR_OUTPUT_ERROR  = 6
_MISSING_ALL_INPUTS = 7
_MISMATCHED_SENSOR_EXPECTED = 8
_CHECK_OUTPUT_ERROR = 9


### Configure Help Pane ###
def ConfigHelp():

	usage = "usage: %prog -n <hostname> -u <userid> -p <password> -s <sensor list> [options]"
	version = "2.0"
	prog = "check_ipmi"
	parser = OptionParser(prog=prog, usage=usage, version=version)
	
	# can't use -h for hostname, optparse detects it as the help command.
	parser.add_option('-n', '--hostname', dest='hostname', action="store", default='127.0.0.1', type='string', help='IP or Hostname of target machine, assumes %default if none is provided.')
	
	# IPMI username and password
	parser.add_option('-u', '--username', dest='username', action="store", default='ADMIN', type='string', help='Username of IPMI Interface.')
	parser.add_option('-p', '--password', dest='password', action="store", default='ADMIN', type='string', help='Password of IPMI Interface.')
	
	# list of comma seperated sensor ID numbers
	parser.add_option('-s', '--sensors', dest='sensor_ids', action="store", default='', type='string', help='Comma seperated list of sensor ID values')
	
	# list of comma seperated strings for the sensor ID numbers included above.
	parser.add_option('-e', '--expected', dest='expected_output', action="store", default = [], type='string', help='(optional) Comma seperated list of expected results for none standard sensor returns ie. (Processor Presence detected,Processor Presence detected,,Unknown). Empty spaces will default to "[OK]".  Must be one entry for each sensor if any are provided. These entries are case insensitive')
	
	# list of comma seperated strings for chassis listings
	parser.add_option('-c', '--chassis', dest='chassis_items', action="store", default = [], type='string', help = '(optional) String value of the chassis entry you wish to monitor.  These entries are case insensitive')
	
	# list of comma seperated strings for chassis expected values
	parser.add_option('-C', '--chassis-values', dest='chassis_values', action="store", default = [], type='string', help = '(optional) String value of the expected output of monitored chassis values.  These entries is case insensitive')
	
	
	#turn on debug mode
	parser.add_option('-d', '--debug', dest = 'debug', action='store_true', default = False, help = 'Turn on debug output')
	
	return parser


def SanityChecks(options):
	if options.sensor_ids == '' and options.chassis_items == []:
		print "Must include a list of sensors or chassis items you'd like to querry"
		return options,_MISSING_ALL_INPUTS
	
	if debug:
		if options.sensor_ids != '': print "options.sensor_ids: " + options.sensor_ids
		if options.chassis_items != []: print "options.chassis_items: " + options.chassis_items
	
	#pre process sensor_ids and sanity check against expected outputs
	if options.sensor_ids != '':
		options.sensor_ids = options.sensor_ids.split(',') #split sensor id's into an array
				
		if options.expected_output or options.expected_output=="":
			options.expected_output = remove_string_brackets(options.expected_output) #this will remove all square brackets from string (legacy correction)
			options.expected_output = options.expected_output.split(',') #split expected output
		else:
			for sensor in options.sensor_ids: options.expected_output.append('') # assume all comparisons against '[OK]', generate list of '' entries
		#check length of sensor_ids and expected output, this is required to catch the 'warning' shade of gray between OK/NA/ERROR (this feels like a kludge, I may explore revising it).
		
		#if (len(options.sensor_ids) != len(options.expected_output) ) and (len(options.expected_output) != 0):
		if (len(options.sensor_ids) != len(options.expected_output) ) and (len(options.expected_output) != 0):
			print "You must provide a value or blank for each sensor requested. Alternatively leave -e out."
			return options,_MISMATCHED_SENSOR_EXPECTED
	
	#pre process chassis lines and expected chassis output
	if options.chassis_items != []:
		options.chassis_items = options.chassis_items.split(',') #generate array of chassis items of interest 
		
		if options.chassis_values == []:
			print "You must provide a list of expected values for chassis items."
			return options,_MISSING_CHASSIS_EXPECTED
		
		options.chassis_values  = options.chassis_values.split(',') #generate array of expected chassis outputs
		
		#if options.chassis_items.length() != options.chassis_values.length():
		if len(options.chassis_items) != len(options.chassis_values):
			print "You must provide an expected output for each chassis item your interested in."
			return options,_MISMATCHED_CHASSIS_EXPECTED
		
		
	#main return if all is well
	return  options,_OK
	
	
def SensorCheck(options):
	sensor_command = 'ipmi-sensors -h ' + options.hostname + ' -u ' + options.username + ' -p ' + options.password + ' -s ' + ','.join(options.sensor_ids) #must rejoin the sensor_ids value so that it is provided to tttthe comand correctly
	
	if debug:
		
		print "command run: " + sensor_command
	
	
	options.sensor_ids = map(int,options.sensor_ids) #cast the strings over to integers	
	sensor_output = getoutput(sensor_command)
	sensor_output = sensor_output.splitlines() #returns an empty set if there is no output.
	
	if debug:
		print "SENSOR_OUTPUT: "
		print  sensor_output
	
	message,check_sensor_error = check_output(sensor_output)
	#if this check fails, error out
	if check_sensor_error:
		if debug:
			print "SENSOR_OUTPUT_ERROR: "
			print message
	
	
		return  message,check_sensor_error #return an error
	
	#generate a tuple structure that can be sorted and manipulated
	sensor_struct = []

	for index in range(len(options.sensor_ids)):
		sensor_struct.append((options.sensor_ids[index],options.expected_output[index]))
	
	#sort afore mentioned structure by id
	sensor_struct.sort()
	
	
	nagios_feed,return_value = process_sensor_output(sensor_output, sensor_struct)
	
	if debug:
		print "SENSOR_CHECK return: "
		print return_value
	
	return nagios_feed,return_value
		

def ChassisCheck(options):
	chassis_command = 'ipmi-chassis -h ' + options.hostname + ' -u ' + options.username + ' -p ' + options.password + ' -s ' 
	
	if debug:
		
		print "CHASSIS_COMMAND_RUN: " + chassis_command
	
	
	
	chassis_output = getoutput(chassis_command)
	chassis_output = chassis_output.splitlines() #returns an empty set if there is no output.
	
	if debug:
		print "CHASSIS_OUTPUT: "
		print  chassis_output
		
	message,check_chassis_error = check_output(chassis_output)
	
	#if this check fails, error out
	if check_chassis_error:
		if debug:
			print "CHASSIS_OUTPUT_ERROR: " + message
		
		
		return  message,check_chassis_error #return an error
	
	#generate a tuple structure that can be sorted and manipulated
	
	
	nagios_feed,return_value = process_chassis_output(chassis_output, options)
	
	if debug:
		print "ChassisCheck return: "
		print return_value
	
	return nagios_feed,return_value


def check_output(ipmi_output):
	# this does a few quick checks to cause the system to error out if there are big problems.
	#it has been updated to handle both sensor and chassis problems instead of implementing 2 seperate check functions.
	
	if ipmi_output == []:
		if debug:
			print "CHECK_OUTPUT: no output recieved"
		return "no output recieved", _CHECK_OUTPUT_ERROR
		
			
	elif ipmi_output[0].find('ipmi-sensors:') != -1 or ipmi_output[0].find('ipmi-chassis:')!= -1 or ipmi_output[0].find('ipmi_open_outofband:') != -1:
		if debug:
			print "CHECK_OUTPUT_FIND_ERROR: "
			print ipmi_output[0]
		return ipmi_output[0], _CHECK_OUTPUT_ERROR
		
	
	else:
		if debug:
			print "CHECK_OUTPUT_NOERROR"
		return '', _OK

		
	
#### Process_output ####
# This function processes the sensor output, and confirms that for each sensor requested, one was returned.
def process_sensor_output(sensor_output, sensor_struct):
	# Setup defaults.
	return_val = _OK
	warning = False
	error = False
	nagios_feed = []
	
	for index in range(len(sensor_struct)):
		# split the sensor id and expected output 
		sensor_id, expected_output = sensor_struct[index]
		
		# the sensor ID should always be compared against the item in location 0, if they ID's match, it will be removed from the list.
		sensor = sensor_output[0]
		sensor = sensor.split(':')
		#if the current sensor id doesn't equal the id of output at this index, generate a warning.
		if sensor == [] or sensor_id != int(sensor[0].strip()): #use short circuit logic to prevent addressing of an empty array
			nagios_feed.append("sensor " + str(sensor_id) + " has no return value") #no performance info for an error :P
			warning = True #set warning flag
		else:
			
			sensor_output.pop(0) # clean up sensor_output, so it's ready for the next step in the loop.
			
			sensor_name = remove_IPMI_units(sensor[1]) #strip junk info like 'celsius' and 'fan'
			sensor_status = 0
			sensor_performance = ''
			# check for the availablity of performance data.
			if len(sensor) == 4:
				sensor_performance = generate_nagios_perfdata(sensor[2])
				sensor_status = check_sensor_status(sensor[3],expected_output)
				if debug:
					print 'Perfdata available for ' + sensor_name + ' (' + sensor_performance + ')'
			else:
				#if no perf data available, just grab the sensor status.
				sensor_performance = ""
				sensor_status = check_sensor_status(sensor[2],expected_output)
				if debug:
					print 'Perfdata not available for ' + sensor_name 
				
			# set warning or error flags if they are relevant.
			if sensor_status == _SENSOR_OUTPUT_WARNING: #flag the warning on.
				warning = True
			elif sensor_status == _SENSOR_OUTPUT_ERROR: #flag the error on.
				error = True
			
			nagios_feed.append(build_feed_string(sensor_name, sensor_status, sensor_performance))
			
		# assemble output string
	
	if warning:
		return_val = _NAGIOS_WARNING
		
	if error:
		return_val = _NAGIOS_ERROR
	
	return nagios_feed, return_val

			
def process_chassis_output(chassis_output, options):
	#current bug: will recognize substrings of larger strings
	#IE, System Power and System Power Overload will both be detected for System Power
	
	#setup defaults
	return_val = 0
	warning = False
	error = False
	nagios_feed = []
	
	for index in range(len(options.chassis_items)):
		
		found = False
		for chassis_output_line in chassis_output:
			
			chassis_entry,chassis_responce = chassis_output_line.split(':')
			chassis_entry=chassis_entry.strip() #remove leading and trailing whitespace
			chassis_responce=chassis_responce.strip() #remove leading and trailing whitespace
			
			#if options.chassis_items[index] in chassis_output_line and options.chassis_values[index] in chassis_output_line: #item in line, expected output in line
			
			if options.chassis_items[index].upper() == chassis_entry.upper() and options.chassis_values[index].upper() == chassis_responce.upper(): #item in line, expected output in line
			
			
				if debug:
					print "PROCESS_CHASSIS_OUTPUT: Item Found and OK"
				found = True
				return_val = _OK
				nagios_feed.append(chassis_output_line)#current implementation not nagios compliant (I don't think?)
			#elif options.chassis_items[index] in chassis_output_line: #item in line, expected output not.
			elif options.chassis_items[index].upper() == chassis_entry.upper(): #item in line, expected output not.
				if debug:
					print "PROCESS_CHASSIS_OUTPUT: Item Found But Wrong"
				found = True
				return_val = _NAGIOS_ERROR
				nagios_feed.append(chassis_output_line) #current implementation not nagios compliant
			
			else:
				if debug:
					print "PROCESS_CHASSIS_OUTPUT: " + options.chassis_items[index].upper() + " not equal to " + chassis_entry.upper() + " ... "
			
		if not found: #requested item not in chassis return structure
			if debug:
				print "PROCESS_CHASSIS_OUTPUT: Item Not Found"
			return_val = _NAGIOS_ERROR
		
	return nagios_feed, return_val



#### build feed string ####
# Simple builds a string based on the sensor name, status and available performance data.
def build_feed_string(sensor_name, sensor_status, sensor_performance):
	
	feed = ""
	
	
	if sensor_status == 0:
		feed = sensor_name + " is OK"
	elif sensor_status == 1:
		feed = sensor_name + " has generated a WARNING"
	else:
		feed = sensor_name + " has generated an ERROR"
	
	if sensor_performance != "":
		feed += " | " + sensor_performance
	
	return feed
	
#### remove ipmi units ####
# strips out junk 'units' in the device name string.	
def remove_IPMI_units(device_string):
	x = device_string.find("(")
	if x == -1:
		device_name = device_string.strip()
	else:
		device_name = device_string[0:x]
		device_name = device_name.strip()
		
	return device_name
	
#### check sensor status against expected ####
# adjust for empty's by testing for 'OK'
def check_sensor_status(sensor_status, expected_status):
	sensor_status = remove_string_brackets(sensor_status) # remove all brackets from sensor status string
	sensor_status = sensor_status.strip() #multiple paths to this point, so strip here.
	sensor_status = sensor_status.upper() #upper case to remove case sensitivities
	expected_status=expected_status.upper() #upper case to remove case sensitivities
	
	if expected_status == '':
		
		if debug:
			print "CHECK_SENSOR_STATUS: Actual: " + sensor_status + " : EXPECTED: OK"
		 
		if sensor_status == 'OK': return _OK # sensor status ok
		elif sensor_status == 'NA': return _SENSOR_OUTPUT_WARNING # generate warning, unknown status
		else: return _SENSOR_OUTPUT_ERROR # sensor status error
	
	else:
		expected_status = expected_status.strip()
		
		if debug:
			print  "CHECK_SENSOR_STATUS: ACTUAL: " + sensor_status + " : EXPECTED: " + expected_status
		
		if sensor_status == expected_status: return _OK# sensor status ok
		else: return _SENSOR_OUTPUT_ERROR # sensor status error
		
			

#### generate nagios performance data ####
# turn any avaiable IPMI performance information into a format better suited to nagios
# layout as: cur val;min val;max val from: 41.00 C (NA/75.00) type format
def generate_nagios_perfdata(raw_perf_data):
	
	raw_perf_data = raw_perf_data.strip()
	
	if debug:
		print 'raw perfdat: ' + raw_perf_data
	
	perfdata = raw_perf_data.split(' ')
	
	perf_value = perfdata[0]
	perf_value = perf_value.strip()
	
	perf_range = perfdata[len(perfdata)-1]
	perf_range = perf_range.strip('(,)')
	perf_range = perf_range.split('/')
	
	performance = perf_value + ';' + perf_range[0] + ';' + perf_range[1]
	
	if debug:
		print 'performance: ' + performance
	
	return performance
	
	
def remove_string_brackets(Xstring):
	Xstring = re.sub('[\[{}\]]','',Xstring) #external brackets encapsulate a set of characters, internal ones must be escaped to be read by interpretter correctly
	return Xstring
	
### Main Procedure ###
# This is the main execution path, this is a procedural program, it runs, it quits, no loop.

def main(argv):
	
	#ErrorCodes() #setup the error codes
	
	parser = ConfigHelp()
	#build usage/help pane
		
	# parse the arguements or argv
	options,args= parser.parse_args(argv)
	
	#setup debug variable
	global debug
	debug = options.debug
	
	options,SanityReturn = SanityChecks(options)
	
	if SanityReturn != _OK: #if it's not a zero, return the value and kick the program for failing sanity checks
		if debug:
			print "Sanity Checks Failed"
		
		return SanityReturn
	
	return_value = _OK  #prime return value to a now issues return
	nagios_feed = []	#prime nagios feed to an empty set.
	
	if options.sensor_ids != '':
		SensorResults,SensorResultsReturn = SensorCheck(options)
		return_value = max(return_value,SensorResultsReturn) #highest error level always preferred
		if debug:
			print "SensorResults:"
			print SensorResults
			print "SensorResultsReturn: "
			print SensorResultsReturn
			
		#nagios_feed.append(SensorResults)
		nagios_feed+=SensorResults
	else:
		SensorResults = ''
		SensorResultsReturn = _OK
	
	if options.chassis_items != []:
		ChassisResults,ChassisResultsReturn = ChassisCheck(options)
		return_value = max(return_value,ChassisResultsReturn) #highest error level always preferred
		if debug:
			print "ChassisResults: "
			print ChassisResults
			print "ChassisReturn: "
			print ChassisResultsReturn
		#nagios_feed += ChassisResults
		#nagios_feed.extend(ChassisResults)
		#nagios_feed.append(ChassisResults)
		nagios_feed+=ChassisResults
	else:
		ChassisResults = ''
		ChassisResultsReturn = _OK
	
	if debug:
		print "nagios_feed:"
		print nagios_feed
	
	for index in range(len(nagios_feed)):
		print nagios_feed[index]
	
	if debug:
		print "return: "
		print return_value
	
	return return_value	

#program 'main' primer.
if __name__ == "__main__":
	sys.exit(main(sys.argv[1:])) #this causes the return of the main function to be the return value of the script.
