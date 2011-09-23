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
	$nrpeuser		= "nagios",
	$nrpegroup 	= "nagios",	
	$nrpedir		= "/etc/nagios",
	$pluginsdir	= "/usr/lib/nagios/plugins"
	) {


	# file { "$pluginsdir/contrib/":
	# 	mode		=> "755",
	# 	source	=> "puppet://$server/modules/nagios-nrpe/plugins/contrib/",
	# 	recurse => true
	# }
	
	$package_server_name = 'nagios-nrpe-server'

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

	service { $package_server_name:
		ensure		=> running,
		enable		=> true,
		pattern		=> "/usr/sbin/nrpe",
		require		=> Package[$package_server_name],
		subscribe => File["$nrpedir/nrpe.cfg"]
	}
}
