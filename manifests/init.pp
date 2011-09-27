# Class: nagios-nrpe
#
# This class installs and configures the nagios NRPE daemon
#
# Parameters:
#		$allowed_hosts:
#			 list of hosts (nagios servers) allowed to contact the NRPE daemon
#
# Actions:
#		Install and configure NRPE
#
# Sample Usage:
#
# History:
#		Initial version from Martha Greenberg marthag@mit.edu http://reductivelabs.com/trac/puppet/wiki/Recipes/Nagios

class nagios_nrpe (
	$allowed_hosts = ['localhost', $server ],	
	$nrpeuser			= "nagios",
	$nrpegroup 		= "nagios",	
	$nrpedir			= "/etc/nagios",
	$pluginsdir		= "/usr/lib/nagios/plugins",
	$nrpe_conf_d	= "/etc/nagios/nrpe.d"
	) {


	# file { "$pluginsdir/contrib/":
	# 	mode		=> "755",
	# 	source	=> "puppet://$server/modules/nagios-nrpe/plugins/contrib/",
	# 	recurse => true
	# }
	
	$package_server_name = 'nagios-nrpe-server'
	$additional_plugins  =[
		'nagios-plugins-basic',
		'nagios-plugins-extra',
		'nagios-plugins',
		'nagios-plugins-standard',
		'nagios-snmp-plugins'
	]
	
	# This is for the PID file
	file { '/var/run/nagios3':
		mode		=> 750,
		owner		=> $nrpeuser,
		group		=> $nrpegroup,
		require	=> Package[$package_server_name],
	}

	file { "$nrpedir/nrpe.cfg":
		mode	=> "644",
		owner		=> $nrpeuser,
		group		=> $nrpegroup,
		require	=> Package[$package_server_name],
		content => template("$module_name/nrpe.cfg.erb")
	}

	package { $package_server_name: 
		ensure 	=> present,
	}
	package { "nagios-nrpe-plugin": 
		ensure	=> present,
		require	=> Package[$package_server_name]
	}
	package { nrpe_plugins:
		name		=> $additional_plugins,
		ensure	=> present,
		require => Package[$package_server_name]
	}

	service { $package_server_name:
		ensure		=> running,
		enable		=> true,
		pattern		=> "/usr/sbin/nrpe",
		require		=> Package[$package_server_name],
		subscribe => File["$nrpedir/nrpe.cfg"]
	}

	###################
	# Ruby Probe Setup
	###################
	package { 'rubygems':
		ensure		=> installed
	}
	package { 'nagios-probe':
		provider	=> 'gem',
		ensure		=> installed,
		require		=> Package['rubygems']
	}
	file { "$pluginsdir/contrib/": 
		ensure	=> directory,
		recurse	=> true,
		mode		=> 755,
		owner		=> $nrpeuser,
		group		=> $nrpegroup,
		source	=> "puppet:///modules/${module_name}/plugins/contrib/",
		require	=> Package['nagios-probe']
	}
	
	########################
	# Support for IPMI/ILOM
	########################
	package{ 'ipmitool': }
	package{ 'freeipmi-common': }
	package{ 'freeipmi-tools': }
	
	file {'/usrbin/ipmi-update-reading-cache.sh':
		source	=> "puppet:///modules/${module_name}/usrbin/ipmi-update-reading-cache.sh",
		mode		=> 755,
		owner		=> 'root',
		group		=> 'root',
		require	=> File['/usrbin']		
	}
}
