#!/usr/bin/env ruby

# This uses the output of the /usrbin/ipmi-update-reading-cache.sh script
# this is so that NRPE reading will be super fast.

require 'ostruct'
require 'getoptlong'

module Nagios
  OK = 0
  WARNING = 1
  CRITICAL = 2
  UNKNOWN = 3

  def self.do_exit prefix, title, msg, code
    $NAGIOS_EXIT = code
    puts "#{prefix}#{title}: #{msg}"
    exit $NAGIOS_EXIT
  end

  def self.fail msg, prefix=''
    Nagios::do_exit prefix, "UNKNOWN", msg, UNKNOWN
  end

  def exit_ok msg, prefix=''
    Nagios::do_exit prefix, "OK", msg, OK
  end

  def exit_warn msg, prefix=''
    Nagios::do_exit prefix, "WARNING", msg, WARNING
  end

  def exit_critical msg, prefix=''
    Nagios::do_exit prefix, "CRITICAL", msg, CRITICAL
  end

  def is_debug?
    $DEBUG
  end

  def dputs msg
    return unless is_debug?
    puts msg
  end
end

class NagiosProbe
  include Nagios
	attr_accessor :args
	
	def initialize
    @args                = OpenStruct.new
    args                 = @args
    args.file            = nil
		args.warn_only       = false
		args.fail_on_missing = true
		args.size_max        = nil
		args.size_min        = nil

    # Parse arguments
    opts = GetoptLong.new(
        [ '--help',               '-h', GetoptLong::NO_ARGUMENT ],
		    [ '--file',               '-F', GetoptLong::REQUIRED_ARGUMENT ],
        [ '--fail-if-not-exist',        GetoptLong::NO_ARGUMENT],
        [ '--warn-if-not-exist',        GetoptLong::NO_ARGUMENT],
        [ '--fail-if-exist',            GetoptLong::NO_ARGUMENT],
        [ '--warn-if-exist',            GetoptLong::NO_ARGUMENT],
        [ '--size-max',                 GetoptLong::REQUIRED_ARGUMENT],
        [ '--size-min',                 GetoptLong::REQUIRED_ARGUMENT]
    )
    opts.each do |opt, arg|
      case opt
        when '--help'
          show_help
          exit Nagios::UNKNOWN
        when '--file'
          args.file = arg
				when '--fail-if-not-exist'	
					args.warn_only       = false	# Fail critical
					args.fail_on_missing = true		# Fail if file does not exist
				when '--warn-if-not-exist'	
					args.warn_only       = true		# Fail warning
					args.fail_on_missing = true		# Fail if file does not exist
				when '--fail-if-exist'
					args.warn_only       = false	# Fail critical
					args.fail_on_missing = false	# Fail if file does exist
		  	when '--warn-if-exist'
					args.warn_only       = true		# Fail warning
					args.fail_on_missing = false	# Fail if file does exist
			  when '--size-max'
					args.size_max = arg.to_i
				when '--size-min'
					args.size_min = arg.to_i
				else
					raise "Unknown Option #{opt}"
      end
    end

    raise "Must specify a file name (-F)" if args.file.to_s.empty?
  end

  def show_help
    puts <<-EOF
===============================================================================
#{File.basename $0} - Check for existance of a file
===============================================================================
Usage: #{File.basename $0} [OPTIONS] -F <file>

Checks for the existance of the file and optionally the file size and will 
fail or warn according to the specified options

Examples:
   Fail if file does not exist:
      #{File.basename $0} /path/to/file.ext

   Fail if files does exists, and if it is :
      #{File.basename $0} --fail-if-exist /path/to/file.ext


Options:
   -h, --help                 This screen
   -F, --File                 Full path to file on local system

Logic Options:
       --fail-if-not-exist    Fail if the file doesn't exist (default)
       --warn-if-not-exist    Warn if the file doesn't exist
       --fail-if-exist        Fail critically if the file does exit
       --warn-if-exist        Warn if the file does exist

Size Operations:
  The size operations are only really usfull with the --XXX-if-exist options 
  and will have no effect if used with the --XXX-if-not-exist options. The
  failures will be determined by the fail/warn-if-exist option you chose.
  You can specify both parameters to do range checking
	
  Size is in bytes
		
       --size-max <size>      Fail if: fsize > <size>
       --size-min <size>      Fail if: fsize < <size>
EOF
  end

  def run
    o = @args
		file_exists = File.exists? o.file
		file_size   = file_exists ? File.size(o.file) : 0
		msg = "File DOES#{file_exists ? "" : " NOT"} exist: #{o.file}"
		prefix = ""
		
		if file_exists then
      # Check for size Failures
      if o.size_min and file_size < o.size_min then
		    msg = "#{msg} (File Size: #{file_size} bytes < #{o.size_min})"
			  size_fail = true
      elsif o.size_max and file_size > o.size_max
		    msg = "#{msg} (File Size: #{file_size} bytes > #{o.size_max})"
			  size_fail = true
      end
			if    size_fail and o.warn_only then
				exit_warn     msg, prefix
			elsif size_fail then
				exit_critical msg, prefix
      end
      # Not a size failure, if we are to fail on missing then it isn't a failure, so exit OK
			exit_ok msg, prefix if o.fail_on_missing
			
			# If we haven't exited then it is not a size issue and fail on exists
			exit_warn     msg, prefix if o.warn_only
			exit_critical msg, prefix
		else
			if o.fail_on_missing then
				exit_warn     msg, prefix if o.warn_only
				exit_critical msg, prefix
			else
				exit_ok       msg, prefix
			end
		end
		
		# WTF?
		fail              msg, prefix
  end
end


##############
# Entry Point
##############
if __FILE__ == $0:
	begin
	  probe = NagiosProbe.new
	  probe.run

    # If here then some unknown voodoo is going on
    Nagios::fail "Wrong Opts? #{probe.args.sensor_reading}", probe.args.prefix
  rescue SystemExit => e
    exit $NAGIOS_EXIT
  rescue Exception => e
    Nagios::fail e
	end
end