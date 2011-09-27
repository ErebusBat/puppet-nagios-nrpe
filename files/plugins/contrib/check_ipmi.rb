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

class IpmiProbe
  include Nagios
	attr_accessor :args
	
	def initialize
    @args               = OpenStruct.new
    args                = @args
    args.hostname       = %x{hostname}.chomp
    args.probe_cache    = "/var/log/ipmi/sensor-reading-cache.#{args.hostname}"
    $NAGIOS_EXIT        = Nagios::UNKNOWN
    args.ok_regex       = ''
    args.warn_regex     = /warn/i
    args.critical_regex = / Asserted/i
    args.prefix         = 'IPMI '
    args.cache_age      = 60

    # Parse arguments
    opts = GetoptLong.new(
        [ '--help',               '-h', GetoptLong::NO_ARGUMENT ],
        [ '--cache',                    GetoptLong::OPTIONAL_ARGUMENT],
        [ '--sensor',             '-S', GetoptLong::REQUIRED_ARGUMENT ],
        [ '--ok-match',           '-O', GetoptLong::OPTIONAL_ARGUMENT ],
        [ '--warn-match',         '-W', GetoptLong::OPTIONAL_ARGUMENT ],
        [ '--critical-match',     '-C', GetoptLong::OPTIONAL_ARGUMENT ],
        [ '--asserted-positive',        GetoptLong::OPTIONAL_ARGUMENT ],
        [ '--asserted-negative',        GetoptLong::OPTIONAL_ARGUMENT ]
    )
    opts.each do |opt, arg|
      case opt
        when '--help'
          raise "NOHELP"
        when '--cache'
          args.probe_cache = arg
        when '--sensor'
          args.sensor = arg
        when '--ok-match'
          args.ok_regex = Regexp.new arg, Regexp::IGNORECASE
        when '--warn-match'
          args.warn_regex = Regexp.new arg, Regexp::IGNORECASE
        when '--critical-match'
          args.critical_regex = Regexp.new arg, Regexp::IGNORECASE
      end
    end

    raise "Must specify a sensor name: --sensor io.hdd0.fail" if args.sensor.to_s.empty?
    raise "Specified probe cache file (--cache) does not exist or can not be read: \"#{args.probe_cache}\"" unless File.readable?(args.probe_cache)
    args.cache_age = args.cache_age.to_i
  end

  def run
    o = @args
    o.sensor_reading = %x{grep -P "#{o.sensor}" #{o.probe_cache}}
    fail "No reading for sensor:#{o.sensor}" if o.sensor_reading.to_s.empty?
    o.sensor_reading.chomp!

    # TODO: Check file age
    cache_mtime = File.mtime(o.probe_cache)
    file_age = Time.now - cache_mtime
    o.is_stale = file_age >= o.cache_age
    o.prefix = "#{o.prefix} STALE>" if o.is_stale

    if is_debug?:
      puts <<-EOF
                 Cache: #{o.probe_cache}
                Sensor: #{o.sensor}
                    OK: #{o.ok_regex}
                  WARN: #{o.warn_regex}
              CRITICAL: #{o.critical_regex}
        Sensor Reading: ==>#{o.sensor_reading}<==
         Max Cache Age: #{o.cache_age}
      Actual Cache Age: #{file_age}
                   Now: #{Time.now}
           Cache mtime: #{cache_mtime}
        Results Stale?: #{o.is_stale}
      EOF
    end

    # Logic is: match worst to best scenarios.
    exit_critical o.sensor_reading, o.prefix if o.critical_regex.match(o.sensor_reading)
    exit_warn o.sensor_reading, o.prefix     if o.warn_regex.match(o.sensor_reading)
    # If OK is specified then try it, otherwise assume OK if got here
    exit_ok o.sensor_reading, o.prefix       if o.ok_regex.to_s.empty? or o.ok_regex.match(o.sensor_reading)
  end
end


##############
# Entry Point
##############
if __FILE__ == $0:
	begin
	  probe = IpmiProbe.new
	  probe.run

    # If here then some unknown voodoo is going on
    Nagios::fail "Wrong Opts? #{probe.args.sensor_reading}", probe.args.prefix
  rescue SystemExit => e
    exit $NAGIOS_EXIT
  rescue Exception => e
    Nagios::fail e
	end
end