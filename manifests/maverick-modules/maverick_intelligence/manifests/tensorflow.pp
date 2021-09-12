# @summary
#   Maverick_intelligence:tensorflow class
#   This class installs/manages the tensorflow Machine Learning software (tensorflow.org).
#
# @example Declaring the class
#   This class is included from maverick_intelligence class and should not be included from elsewhere
#
# @param source
#   Github repo to use when compiling from source.
# @param source_version
#   Github tag/branch to use when compiling from source.
# @param bazel_version
#   Version of bazel to use when compiling from source.
# @param version
#   Major version to use - 1 or 2.  Now defaults to 2.
# @param arch
#   Force architecture to use when installing from binary on raspberry.  Useful when preparing Pi Zero/Lite image on a Pi 3/4 board for speed.
# @param install_type
#   Force type of install - source or binary (pip wheel).
#
class maverick_intelligence::tensorflow (
    String $source = "https://github.com/tensorflow/tensorflow.git",
    String $source_version = "v2.6.0",
    String $bazel_version = "3.4.1",
    String $binary_version = "2.6.0",
    Optional[Enum['armv6l', 'armv7l']] $arch = undef,
    Optional[Enum['pip', 'source']] $install_type = undef,
) {

    # Work out if source is install is necessary
    if ! empty($install_type) {
        $_install_type = $install_type
    } if ($architecture == "amd64" or $architecture == "i386" or $raspberry_present == "yes" or $tegra_present == "yes") {
        $_install_type = "pip"
    } else {
        $_install_type = "source"
    }

    ensure_packages(["libblas-dev", "liblapack-dev", "libatlas-base-dev", "gfortran", "libhdf5-dev"])

    # Ensure package dependencies are installed
    install_python_module { "tensorflow-numpy":
        pkgname     => "numpy",
        ensure      => present,
    }
    install_python_module { "tensorflow-cython":
        pkgname     => "cython",
        ensure      => present,
    }

    if $_install_type == "pip" {
        if ($::raspberry_present == "yes" and $::architecture == "armv7l") or $arch == "armv7l"  {
            $tensorflow_url = "https://github.com/PINTO0309/Tensorflow-bin/raw/master/tensorflow-2.1.0-cp37-cp37m-linux_armv7l.whl"
        } elsif ($::raspberry_present == "yes" and $::architecture == "armv6l") or $arch == "armv6l" {
            warning("No tensorflow install available for Pi Zero/armv6l")
        } elsif ($::tegra_present == "yes") {
            $tensorflow_url = "https://github.com/PINTO0309/Tensorflow-bin/raw/master/tensorflow-2.1.0-cp37-cp37m-linux_aarch64.whl"
        } else {
            $tensorflow_url = ""
            $tensorflow_pkgname = "tensorflow"
        }

        if $tensorflow_url == "" {
            install_python_module { "tensorflow-pip":
                pkgname     => $tensorflow_pkgname,
                ensure      => present,
                timeout     => 0,
            }
        } else {
            install_python_module { "tensorflow-pip":
                pkgname     => "tensorflow",
                url         => $tensorflow_url,
                ensure      => present,
                timeout     => 0,
                require     => Install_python_module["tensorflow-cython"],
            }
        }

    } elsif $_install_type == "source" {
        if ! ("install_flag_tensorflow" in $installflags) {
            ensure_packages(["openjdk-8-jdk", "zlib1g-dev", "swig"])
            # Set variables per platform, tensorbuild is quite specific per platform due to the numebr of kludges necessary
            if $architecture == "amd64" {
                $java_home = "/usr/lib/jvm/java-8-openjdk-amd64"
            } elsif $architecture == "armv7l" or $architecture == "armv6l" {
                $java_home = "/usr/lib/jvm/java-8-openjdk-armhf"
            } else {
                $java_home = ""
            }

            file { "/srv/maverick/var/build/tensorflow":
                ensure      => directory,
                owner       => "mav",
                group       => "mav",
                mode        => "755",
            } ->
            # Install bazel.  This is a bit hacky, due to the wierd way bazel decides to distribute itself..
            exec { "download-bazel":
                command     => "/usr/bin/wget https://github.com/bazelbuild/bazel/releases/download/${bazel_version}/bazel-${bazel_version}-dist.zip",
                cwd         => "/srv/maverick/var/build/tensorflow",
                creates     => "/srv/maverick/var/build/tensorflow/bazel-${bazel_version}-dist.zip",
                user        => "mav",
            } ->
            file { "/srv/maverick/var/build/tensorflow/bazel":
                owner       => "mav",
                group       => "mav",
                mode        => "755",
                ensure      => directory,
            } ->
            exec { "unzip-bazel":
                command     => "/usr/bin/unzip /srv/maverick/var/build/tensorflow/bazel-${bazel_version}-dist.zip -d /srv/maverick/var/build/tensorflow/bazel",
                cwd         => "/srv/maverick/var/build/tensorflow",
                user        => "mav",
                creates     => "/srv/maverick/var/build/tensorflow/bazel/README.md",
            }
            if Numeric($::memorysize_mb) < 2000 {
                exec { "patch-compilesh-lowmem":
                    command     => "/bin/sed -i -e 's/-encoding UTF-8/-encoding UTF-8 -J-Xms256m -J-Xmx512m/' /srv/maverick/var/build/tensorflow/bazel/scripts/bootstrap/compile.sh",
                    unless      => "/bin/grep -e '-J-Xms256m -J-Xmx512m' /srv/maverick/var/build/tensorflow/bazel/scripts/bootstrap/compile.sh",
                    user        => "mav",
                    before      => Exec["compile-bazel"],
                    require     => Exec["unzip-bazel"],
                }
            }
            exec { "compile-bazel":
                environment => "JAVA_HOME=$java_home",
                command     => "/srv/maverick/var/build/tensorflow/bazel/compile.sh >/srv/maverick/var/log/build/bazel.compile.log 2>&1",
                cwd         => "/srv/maverick/var/build/tensorflow/bazel",
                user        => "mav",
                timeout     => 0,
                creates     => "/srv/maverick/var/build/tensorflow/bazel/output/bazel",
                require     => [ Exec["unzip-bazel"], Package["openjdk-8-jdk"] ],
            } ->
            # Install tensorflow
            oncevcsrepo { "git-tensorflow":
                gitsource   => $source,
                dest        => "/srv/maverick/var/build/tensorflow/tensorflow",
                revision    => $source_version,
                submodules  => true,
            }
            # Do some hacks for arm build
            if $raspberry_present == "yes" or $odroid_present == "yes" {
                /*
                exec { "tfhack-lib64":
                    command     => "/bin/grep -Rl 'lib64' | xargs sed -i 's/lib64/lib/g'",
                    onlyif      => "/bin/grep lib64 /srv/maverick/var/build/tensorflow/tensorflow/tensorflow/core/platform/default/platform.bzl",
                    cwd         => "/srv/maverick/var/build/tensorflow/tensorflow",
                    user        => "mav",
                } ->
                exec { "tfhack-mobiledev":
                    command     => "/bin/sed -i '/IS_MOBILE_PLATFORM/d' tensorflow/core/platform/platform.h",
                    onlyif      => "/bin/grep IS_MOBILE_PLATFORM tensorflow/core/platform/platform.h",
                    cwd         => "/srv/maverick/var/build/tensorflow/tensorflow",
                    user        => "mav",
                } ->
                exec { "tfhack-https-cloudflare":
                    command     => "/bin/sed -i 's#https://cdnjs#http://cdnjs#' WORKSPACE",
                    onlyif      => "/bin/grep 'https://cdnjs' WORKSPACE",
                    cwd         => "/srv/maverick/var/build/tensorflow/tensorflow",
                    user        => "mav",
                    before      => Exec["configure-tensorflow"],
                }
                */
                $copts = '--copt="-mfpu=neon-vfpv4" --copt="-funsafe-math-optimizations" --copt="-ftree-vectorize" --copt="-fomit-frame-pointer"'
                $resources = '768,0.5,1.0'
            } else {
                $copts = ''
                $resources = '1024,0.5,1.0'
            }
            exec { "configure-tensorflow":
                environment => [
                    "PYTHON_BIN_PATH=/usr/bin/python", 
                    "PYTHON_LIB_PATH=/usr/local/lib/python2.7/dist-packages", 
                    "TF_NEED_MKL=0",
                    "TF_NEED_JEMALLOC=1",
                    "TF_NEED_GCP=0",
                    "TF_NEED_HDFS=0",
                    "TF_NEED_VERBS=0",
                    "TF_NEED_OPENCL=0",
                    "TF_NEED_CUDA=0",
                    "TF_ENABLE_XLA=0",
                    "CC_OPT_FLAGS=\"-march=native\"",
                    "PATH=/srv/maverick/var/build/tensorflow/bazel/output:/usr/bin:/bin",
                ],
                command     => "/bin/bash /srv/maverick/var/build/tensorflow/tensorflow/configure",
                cwd         => "/srv/maverick/var/build/tensorflow/tensorflow",
                user        => "mav",
                timeout     => 0,
                creates     => "/srv/maverick/var/build/tensorflow/tensorflow/.tf_configure.bazelrc",
                require     => Oncevcsrepo["git-tensorflow"],
            } ->
            exec { "compile-tensorflow":
                command     => "/srv/maverick/var/build/tensorflow/bazel/output/bazel build --config=opt ${copts} --local_resources ${resources} --verbose_failures //tensorflow/tools/pip_package:build_pip_package >/srv/maverick/var/log/build/tensorflow.compile.log 2>&1",
                cwd         => "/srv/maverick/var/build/tensorflow/tensorflow",
                user        => "mav",
                timeout     => 0,
                #creates     => "/srv/maverick/var/build/tensorflow/tensorflow/bazel-bin",
            } ->
            exec { "createwhl-tensorflow":
                command     => "/srv/maverick/var/build/tensorflow/tensorflow/bazel-bin/tensorflow/tools/pip_package/build_pip_package /srv/maverick/var/build/tensorflow/tensorflow_pkg >/srv/maverick/var/log/build/tensorflow.createwhl.log 2>&1",
                cwd         => "/srv/maverick/var/build/tensorflow/tensorflow",
                user        => "mav",
                timeout     => 0,
                creates     => "/srv/maverick/var/build/tensorflow/tensorflow_pkg",
            }
            unless "tensorflow" in $::python_modules["global"] {
                exec { "install-tensorflow":
                    path        => ["/usr/local/bin","/usr/bin"],
                    command     => "pip --disable-pip-version-check install /srv/maverick/var/build/tensorflow/tensorflow_pkg/*.whl >/srv/maverick/var/log/build/tensorflow.install.log 2>&1",
                    require     => Exec["createwhl-tensorflow"],
                    before      => File["/srv/maverick/var/build/.install_flag_tensorflow"],
                }
            }
            file { "/srv/maverick/var/build/.install_flag_tensorflow":
                owner       => "mav",
                group       => "mav",
                mode        => "644",
                ensure      => present,
                require     => Exec["createwhl-tensorflow"],
            }
        }
    }
}
