# @summary
#   Base::Maverick class
#   This class sets up the basic Maverick environment - mav user, /srv/maverick directory structure, git branch, base containers for status,
#   various scripts and symlinks, and in bootstrap it clones the Maverick software itself (/srv/maverick/software/maverick)
#
# @example Declaring the class
#   This class is included from base class and should not be included from elsewhere
#
# @param maverick_branch
#   This determines which git branch is used for Maverick software (/srv/maverick/software/maverick)
# @param git_credentials_cache
#   Whether to use credentials cache.  Unless using a shared machine set to true, to stop having to re-enter git credentials every push.
#
class base::maverick (
    String $maverick_url = "https://github.com/goodrobots/maverick.git",
    String $maverick_branch = "stable",
    Boolean $git_credentials_cache = true,
) {

    # Note: The mav user is setup in base::users
    file { ["/srv/", "/srv/maverick", "/srv/maverick/software", "/srv/maverick/code", "/srv/maverick/code/maverick", "/srv/maverick/code/maverick/custom-modules", "/srv/maverick/data", "/srv/maverick/data/logs", "/srv/maverick/config", "/srv/maverick/config/maverick", "/srv/maverick/config/maverick/local-nodes", "/srv/maverick/var", "/srv/maverick/var/build", "/srv/maverick/var/log", "/srv/maverick/var/log/build", "/srv/maverick/var/log/maverick", "/srv/maverick/var/run", "/srv/maverick/var/lib", "/srv/maverick/.virtualenvs"]:
        ensure  => directory,
        owner   => "mav",
        group   => "mav",
        mode    => "755",
    }

    # If the gitbranch fact is set, use that to set the branch while setting up maverick
    if $::gitbranch {
        $_giturl = $::giturl
    } else {
        $_giturl = $maverick_url
    }

    if $::gitbranch {
        $_gitbranch = $::gitbranch
    } else {
        $_gitbranch = $maverick_branch
    }

    # Setup git for the mav user
    include git
    # Lay down a default .gitconfig for mav user, don't overwrite modifications in the future
    file { "/srv/maverick/.gitconfig":
        content         => template("base/mav_gitconfig.erb"),
        owner           => "mav",
        group           => "mav",
        mode            => "644",
        replace         => false,
    }

    # Pull maverick into it's final resting place
    oncevcsrepo { "git-maverick":
        gitsource   => $_giturl,
        dest        => "/srv/maverick/software/maverick",
        revision    => $_gitbranch,
    } ->
    file { "/srv/maverick/software/maverick/conf/devices":
        ensure  => directory,
        group   => "mav",
    }
    file { "/srv/maverick/config/maverick/localconf.json":
        source      => "puppet:///modules/base/maverick-localconf.json",
        mode        => "644",
        owner       => "mav",
        group       => "mav",
        replace     => false,
    } ->
    file { "/etc/profile.d/maverick-call.sh":
        ensure      => present,
        mode        => "644",
        owner       => "root",
        group       => "root",
        content     => "maverick() { /srv/maverick/software/maverick/bin/maverick \$1 \$2 \$3 \$4; . /etc/profile; }",
    }
    exec { "sudoers-securepath":
        command     => '/bin/sed /etc/sudoers -i -r -e \'s#"$#:/srv/maverick/software/maverick/bin:/srv/maverick/software/python/bin"#\'',
        unless      => "/bin/grep 'secure_path' /etc/sudoers |/bin/grep 'software/maverick/bin.*software/python/bin'"
    }

    # Add environment marker
    file { "/srv/maverick/config/maverick/maverick-environment.conf":
        ensure      => file,
        owner       => "mav",
        group       => "mav",
        mode        => "644",
        content     => $environment,
    }

    # Start a concat file for maverick paths
    concat { "/etc/profile.d/maverick-path.sh":
        ensure      => present,
    }
    concat::fragment { "maverickpath-base":
        target      => "/etc/profile.d/maverick-path.sh",
        order       => 1,
        content     => 'NEWPATH="/srv/maverick/software/maverick/bin"; if [ -n "${PATH##*${NEWPATH}}" -a -n "${PATH##*${NEWPATH}:*}" ]; then export PATH=$NEWPATH:$PATH; fi',
    }

    # Create status.d directory for `maverick status`
    file { "/srv/maverick/software/maverick/bin/status.d":
        ensure      => directory,
        owner       => "mav",
        group       => "mav",
        mode        => "755",
        require => Oncevcsrepo["git-maverick"],
    }

    # Create symlinks for maverick subcommands
    file { "/srv/maverick/software/maverick/bin/maverick-info":
        ensure  => link,
        target  => "/srv/maverick/software/maverick/manifests/maverick-modules/base/files/maverick-info",
        require => Oncevcsrepo["git-maverick"],
    }
    file { "/srv/maverick/software/maverick/bin/maverick-netinfo":
        ensure  => link,
        target  => "/srv/maverick/software/maverick/manifests/maverick-modules/maverick_network/files/maverick-netinfo",
        require => Oncevcsrepo["git-maverick"],
    }
    file { "/srv/maverick/software/maverick/bin/wifi-setup":
        ensure  => link,
        target  => "/srv/maverick/software/maverick/manifests/maverick-modules/maverick_network/files/wifi-setup",
        require => Oncevcsrepo["git-maverick"],
    }

    # Remove old branch file
    exec { "move-oldbranchfile":
        command     => "/bin/mv /srv/maverick/config/maverick-branch.conf /srv/maverick/config/maverick",
        onlyif      => "/bin/ls /srv/maverick/config/maverick-branch.conf",
    } ->
    # Add maverick git branch config
    file { "/srv/maverick/config/maverick/maverick-branch.conf":
        owner   => "mav",
        group   => "mav",
        content => "MAVERICK_BRANCH=${_gitbranch}",
        replace => false,
    }

    # Migrate old fnoop origin to goodrobots
    exec { "mavfnoop-to-mavgoodrobots":
        command => "/usr/bin/git remote set-url origin https://github.com/PYBrulin/maverick.git",
        onlyif  => "/usr/bin/git remote -v |grep fnoop",
    }

    # Ensure desktop config directory exists and prevent auto directory creation
    file { "/srv/maverick/.config":
        owner   => "mav",
        group   => "mav",
        mode    => "755",
        ensure  => directory,
    } ->
    file { "/srv/maverick/.config/user-dirs.conf":
        owner   => "mav",
        group   => "mav",
        mode    => "644",
        content => "enabled=False",
    }

    file { "/srv/maverick/.cache":
        ensure  => directory,
        owner   => "mav",
        group   => "mav",
    } ->

    # Create a 'firstboot' service that runs on boot and calls configure if required
    file { "/etc/systemd/system/maverick-firstboot.service":
        source      => "puppet:///modules/base/maverick-firstboot.service",
        owner       => "root",
        group       => "root",
        mode        => "644",
        notify      => Exec["maverick-systemctl-daemon-reload"],
    } ->
    service { "maverick-firstboot": 
        enable      => true,
        ensure      => undef,
    }

}
