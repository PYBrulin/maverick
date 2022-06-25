# @summary
#   Base::Python class
#   This class installs/manages Python software.
#   It manages the system python to some degree, but it focuses on providing a custom optimised python build installed into /srv/maverick/software/python.
#   This currently installs the latest point release of Python 3.8.
#
# @example Declaring the class
#   This class is included from base class and should not be included from elsewhere
#
# @param maverick_python
#   Whether to install the custom Maverick Python instance.  This should always be true, unless the OS provides a trusted 3.8 instance.
# @param python_version
#   The custom version of Python to compile and install.
#
class base::python (
    Boolean $maverick_python = true,
    String $python_version = "v3.8.12",
) {

    # Install custom python 3.8
    # It is STRONGLY recommended not to disable this - Maverick and associated projects target python 3.8+
    if $maverick_python == true {
        # If ~/var/build/.install_flag_python exists, skip pulling source and compiling
        if ! ("install_flag_python" in $installflags) {
            warning("Optimized Python3 will be built and can take a long time, please be patient..")
            # Pull python from git
            ensure_packages(["libssl-dev", "libffi-dev", "libncurses5-dev", "libncursesw5-dev", "libgdbm-dev", "libreadline-dev", "tk-dev", "liblzma-dev", "libbz2-dev", "libsqlite3-dev", "libatlas-base-dev"])
            oncevcsrepo { "git-python":
                gitsource   => "https://github.com/python/cpython.git",
                dest        => "/srv/maverick/var/build/python",
                revision    => $python_version,
            } ->
            exec { "python-configure":
                environment => ["LDFLAGS=-Wl,-rpath,/srv/maverick/software/python/lib"],
                command     => "/srv/maverick/var/build/python/configure --prefix=/srv/maverick/software/python --enable-optimizations --with-lto --enable-shared >/srv/maverick/var/log/build/python.configure.out 2>&1",
                cwd         => "/srv/maverick/var/build/python",
                creates     => "/srv/maverick/var/build/python/Makefile",
                user        => "mav",
                timeout     => 0,
                require     => [ Package["libffi-dev"], Package["tk-dev"], Package["libbz2-dev"], Package["libssl-dev"], ],
            } ->
            exec { "python-make":
                environment => ["LDFLAGS=-Wl,-rpath,/srv/maverick/software/python/lib", "PROFILE_TASK=-m test.regrtest --pgo -j${::processorcount}"],
                command     => "/usr/bin/make -j${::processorcount} >/srv/maverick/var/log/build/python.make.out 2>&1",
                cwd         => "/srv/maverick/var/build/python",
                creates     => "/srv/maverick/var/build/python/libpython3.so",
                user        => "mav",
                timeout     => 0,
            } ->
            exec { "python-make-install":
                environment => ["LDFLAGS=-Wl,-rpath,/srv/maverick/software/python/lib"],
                command     => "/usr/bin/make install >/srv/maverick/var/log/build/python.make.install.out 2>&1",
                cwd         => "/srv/maverick/var/build/python",
                creates     => "/srv/maverick/software/python/bin/python3",
                user        => "mav",
                timeout     => 0,
                before      => File["/srv/maverick/software/python/bin/python"],
            } ->
            exec { "python-pip-upgrade":
                cwd         => "/srv/maverick/software/python",
                command     => "/srv/maverick/software/python/bin/pip3 install --upgrade pip",
                user        => "mav",
            } ->
            file { "/srv/maverick/var/build/.install_flag_python":
                ensure      => present,
            }
        }

        # This makes the custom python3 the system default, at least by path invocation
        file { "/etc/profile.d/99-maverick-python-path.sh":
            owner   => "root",
            group   => "root",
            mode    => "0644",
            content => 'NEWPATH="/srv/maverick/software/python/bin"; export PATH=${PATH:-${NEWPATH}}; if [ -n "${PATH##*${NEWPATH}}" -a -n "${PATH##*${NEWPATH}:*}" ]; then export PATH=$NEWPATH:$PATH; fi',
        }

        # Add a 'python' symlink to python3, to satisfy all those scripts that invoke python in their hashbang
        file { "/srv/maverick/software/python/bin/python":
            target  => "/srv/maverick/software/python/bin/python3",
        }

    }

    # Temporarily, we still need python-pip for some python2 pips (vision_landing)
    #  https://github.com/goodrobots/maverick/issues/995
    # But python2 doesn't exist anymore in ubuntu 20.04 onwards
    if $::operatingsystem == "Ubuntu" and versioncmp($::operatingsystemmajrelease, "20") == 0 {
        package { "python-pip":
            ensure      => present,
        }
    }

    # Install basic useful python modules
    # These all install into python3
    install_python_module { 'pip-setuptools':
        pkgname     => "setuptools",
        ensure      => atleast,
        version     => '49.1.3',
    } ->
    install_python_module { 'pip-isort':
        pkgname     => "isort",
        ensure      => atleast,
        version     => '5.1.2',
    } ->
    install_python_module { 'pip-numpy':
        pkgname     => 'numpy',
        ensure      => present,
    } ->
    install_python_module { 'pip-daemon':
        pkgname     => 'python-daemon',
        ensure      => present,
    } ->
    install_python_module { 'pip-lockfile':
        pkgname     => 'lockfile',
        ensure      => present,
    } ->
    install_python_module { "pytest":
        pkgname     => "pytest",
        ensure      => present,
        timeout     => 0,
    } ->
    install_python_module { "pip-yaml":
        pkgname     => "PyYAML",
        ensure      => exactly,
        version     => "3.13",
        timeout     => 0,
    } ->
    install_python_module { "pip-pylint":
        pkgname     => "pylint",
        ensure      => present,
        timeout     => 0,
    } ->
    install_python_module { "pip-virtualenvwrapper":
        pkgname     => "virtualenvwrapper",
        ensure      => present,
        timeout     => 0,
    } ->
    install_python_module { "pip-black":
        pkgname     => "black",
        ensure      => present,
        timeout     => 0,
    } ->
    install_python_module { "pip-flake8":
        pkgname     => "flake8",
        ensure      => present,
        timeout     => 0,
    } ->
    install_python_module { "pip-pexpect":
        pkgname     => "pexpect",
        ensure      => present,
        timeout     => 0,
    } ->
    install_python_module { 'pip-requests':
        pkgname     => 'requests',
        ensure      => present,
        timeout     => 0,
    }

    # Install PyRIC and netifaces, python modules necessary to run maverick --netinfo
    install_python_module { 'pip-pyric':
        pkgname     => 'PyRIC',
        ensure      => present,
    } ->
    install_python_module { 'pip-netifaces':
        pkgname     => 'netifaces',
        ensure      => present,
    } ->
    install_python_module { 'pip-future':
        pkgname     => 'future',
        ensure      => present,
    }
}
