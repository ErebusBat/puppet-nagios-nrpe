# Class: nagios-nrpe
#
# This class installs and configures the nagios NRPE daemon
#
# Parameters:
#   $allowed_hosts:
#      list of hosts (nagios servers) allowed to contact the NRPE daemon
#
# Actions:
#   Install and configure NRPE
#
# Sample Usage:
#
# History:
# 	Initial version from Martha Greenberg marthag@mit.edu http://reductivelabs.com/trac/puppet/wiki/Recipes/Nagios

class nagios-nrpe {

	$allowed_hosts = ['localhost', 'nms.sv1.centralhost.com']
    $nrpeservice = "nrpe"
    $nrpepattern = "nrpe"
    $nrpepackage = "nrpe"
    $nrpedir     = "/etc/nagios"
    $nrpeuser  = "nrpe"
    $nrpegroup = "nrpe"
    $pluginsdir  = "/usr/lib/nagios/plugins"

	file {
		"$pluginsdir/contrib/":
    		mode    => "755",
    		source  => "puppet://$server/nagios-nrpe/plugins/contrib/",
		`	recurse => true
  	}

  	file {
		"$nrpedir/nrpe.cfg":
			mode 	=> "644",
			require => Package[$nrpepackage],
			owner 	=> $nrpeuser,
			group 	=> $nrpegroup,
			content => template("nagios-nrpe/nrpe.cfg")
	}

	package {
		$nrpepackage: ensure => present;
		"nagios-plugins-all": ensure => present;
		"nagios-plugins-nrpe": ensure => present;
	}

	service { 
		"$nrpeservice":
    		ensure    => running,
    		enable    => true,
    		pattern   => "$nrpepattern",
    		subscribe => File["$nrpedir/nrpe.cfg"]
  	}
}
