#!/usr/bin/env ruby

# This uses the output of the /usrbin/ipmi-update-reading-cache.sh script
# this is so that NRPE reading will be super fast.

require 'rubygems'
require 'nagios-probe'

DEBUG=$DEBUG
MAX_NUM=9999999
class BaseProbe < Nagios::Probe	
	alias :super_run :run
	def run
		decode_argvs
		gather
		super_run
	end
	
	def decode_argvs argv=nil
	end
	
	def range_from_nagios_threshold thres
		case thres
		when /([0-9]+)/
			Range.new 0, $1.to_i
		when /([0-9]+):/
			Range.new $1.to_i, MAX_NUM
		when /~:([0-9]+)/
			Range.new $1.to_i.next, MAX_NUM
		when /@([0-9]+):([0-9]+)/
			Range.new $1.to_i, $2.to_i
		else
			raise "I don't know how to parse: $thres"
		end
	end
	
	def is_debug?
		DEBUG
	end
	def debug msg
		puts msg if is_debug?
	end
	
	def round num,prec=0
		return num.to_f.round if prec==0
		prec_num = (10**prec).to_f
		(num * prec_num).round() / prec_num
	end
	def to_pct num, total
		round num/total.to_f*100, 2
	end
end

class MyProbe < BaseProbe	
	attr_accessor :ok_string, :sensor, :reading
	
	def initialize	
		@ok_string = "[OK]"
	end
	
	def decode_argvs argv=nil
		argv = ARGV unless argv
		while argv.count > 0
			current = argv.shift
			case current
			when /^-s /,
			     /^--sensor/ 
				@sensor = argv.shift
			else
				raise "Unknown parameter: #{current}"
			end
		end
	end
	
	
	def gather		
		@reading = %x{grep #{@sensor}: /root/.freeipmi/sensor-reading-cache}		
	end
	
	def check_crit
    return true unless @reading
		@reading.match(@ok_string) == false
  end

  def check_warn
		@reading.match(@ok_string) == false
  end

  def crit_message
		@reading
  end

  def warn_message
		@reading
  end

  def ok_message
		@reading
  end
end

if __FILE__ == $0:
	begin
	  probe = MyProbe.new
	  probe.run
	rescue Exception => e
	  puts "Unknown: " + e
	  exit Nagios::UNKNOWN
	end

	puts probe.message
	exit probe.retval
end