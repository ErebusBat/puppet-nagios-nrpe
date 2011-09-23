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

class nagios-nrpe (
	$allowed_hosts = ['localhost', $server ],	
	$nrpeuser		= "nrpe",
	$nrpegroup 	= "nrpe",	
	$nrpedir		= "/etc/nagios",
	$pluginsdir	= "/usr/lib/nagios/plugins"
	) {


	# file { "$pluginsdir/contrib/":
	# 	mode		=> "755",
	# 	source	=> "puppet://$server/modules/nagios-nrpe/plugins/contrib/",
	# 	recurse => true
	# }

	file { "$nrpedir/nrpe.cfg":
		mode	=> "644",
		require => Package['nrpe'],
		owner		=> $nrpeuser,
		group		=> $nrpegroup,
		require	=> Package['nrpe'],
		content => template("nagios-nrpe/nrpe.cfg")
	}

	package { "nrpe": 
		ensure 	=> present,
	}
	package { "nagios-plugins-nrpe": 
		ensure	=> present,
		require	=> Package['nrpe']
	}
	package { "nagios-plugins-all": 
		ensure 	=> present,
		require	=> Package['nagios-plugins-nrpe']				
	}

	service { nrpe:
		ensure		=> running,
		enable		=> true,
		pattern		=> "nrpe",
		require		=> Package['nrpe']
		subscribe => File["$nrpedir/nrpe.cfg"]
	}
}
