#!/usr/bin/env ruby
# See also http://pastebin.com/RAZkxhY2
# https://github.com/hobodave/nagios-probe/blob/master/lib/nagios-probe.rb
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
	attr_accessor :mem_free, :mem_used, :mem_total, :critical_range, :warning_range
	
	def initialize		
		@critical_range = Range.new 0,0
		@warning_range  = Range.new 0,0
		@mem_free		= [0,0]
		@mem_used		= [0,0]
		@mem_total 	= 0
	end
	
	def decode_argvs argv=nil
		argv = ARGV unless argv
		while argv.count > 0
			current = argv.shift
			case current
			when '-c'
				@critical_range = range_from_nagios_threshold argv.shift
			when '-w'
				@warning_range = range_from_nagios_threshold argv.shift
			else
				raise "Unknown parameter: $current"
			end
		end
	end
	
	
	def gather		
		# @mem_free		= [0,0]
		# @mem_used		= [0,0]
		# @mem_total 	= 0
		mem = %x{free -tm} unless is_debug?
		mem = %Q{
             total       used       free     shared    buffers     cached
Mem:          8001        448       7553          0         51        143
-/+ buffers/cache:        253       7748
Swap:        17099          0      17099
Total:       25101        448      24653
} if is_debug?
		match = mem.match /Mem:\s+(\d+)\s+(\d+)\s+(\d+)/
		raise "couldn't match!" unless match && match.length==4
 		debug "MATCH! t=#{match[1]} u=#{match[2]} f=#{match[3]}"
		@mem_free[0] = match[1].to_i
		@mem_used[0] = match[2].to_i
		@mem_total   = match[3].to_i 
		
		@mem_free[1] = to_pct @mem_free[0], @mem_total
		@mem_used[1] = to_pct @mem_used[0], @mem_total
		debug "Total: 	#{@mem_total} MB"
		debug " Free: 	#{@mem_free[0]} MB/#{@mem_free[1]}%"
		debug " Used: 	#{@mem_used[0]} MB/#{@mem_used[1]}%"
	end
	
  def check_crit
    return true unless @mem_total # fail if we didn't match
		@critical_range === @mem_free
  end

  def check_warn
    return true unless @mem_total # fail if we didn't match
		@warning_range === @mem_free
  end

  def crit_message
		return "Could not parse result of free" unless @mem_free
		"#{@mem_used[0]}MB/#{@mem_total[0]}MB (#{@mem_free[0]}MB, #{@mem_free[1]}% free)"
  end

  def warn_message
		crit_message
  end

  def ok_message
    "Used #{@mem_used[0]} MB/#{@mem_used[1]}% out of #{@mem_total} MB"
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