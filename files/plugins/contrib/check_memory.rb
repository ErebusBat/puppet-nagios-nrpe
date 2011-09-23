#!/usr/bin/env ruby
# See also http://pastebin.com/RAZkxhY2
# https://github.com/hobodave/nagios-probe/blob/master/lib/nagios-probe.rb
require 'rubygems'
require 'nagios-probe'

MAX_NUM=9999999
class BaseProbe < Nagios::Probe	
	def run
		decode_argvs
		gather
		super.run	
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
end

class MyProbe < BaseProbe	
	@critical_range = Range.new 0,0
	@warning_range  = Range.new 0,0
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
	
	@mem_free		= [0,0]
	@mem_used		= [0,0]
	@mem_total 	= 0
	def gather
		puts "Gathering..."
		mem = %x{free -tm}
		match = mem.match /^Total:\s+(\d+)\s+(\d+)\s+(\d+)/
		raise "couldn't match!" unless match
 		puts match
		puts @mem_free[0]
		@mem_free[0] = match[1].to_i
		#@mem_used[0] = match[2].to_i
		#@mem_total   = match[3].to_i 
		
		#@mem_free[1] = @mem_free[0] / @mem_total
		# @mem_used[1] = @mem_used[0] / @mem_total
		puts "Total: 	#{@mem_total}MB"
		# puts " Free: 	#{@mem_free[0]}MB/#{@mem_free[1]}%"
		# puts " Used: 	#{@mem_used[0]}MB/#{@mem_used[1]}%"
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
    "Memory usage optimal"
  end
end

begin
  options = {} # Nagios::Probe constructor accepts a single optional param that is assigned to @opts
  probe = MyProbe.new(options)
  probe.run
rescue Exception => e
  puts "Unknown: " + e
  exit Nagios::UNKNOWN
end

puts probe.message
exit probe.retval