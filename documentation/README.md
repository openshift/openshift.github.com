# OpenShift Origin Build Tools

Origin-dev-tools contains the scripts necessary for building OpenShift Origin PaaS from source. 

## Usage

The build tools require rubygem-thor and git to be installed:

		yum install -y rubygem-thor git

The tools can be invoked using [/build/devenv](https://github.com/openshift/origin-dev-tools/blob/master/build/devenv) script.

### EC2 build and test options

  * ./build/devenv build [NAME] [BUILD_NUM]

	Build a new devenv AMI with the given NAME

		Options:
		  [--register]                             # Register the instance
		  [--terminate]                            # Terminate the instance on exit
		  [--branch=BRANCH]                        # Build instance off the specified branch
		                                           # Default: master
		  [--yum-repo=YUM_REPO]                    # Build instance off the specified yum repository
		                                           # Default: candidate
		  [--reboot]                               # Reboot the instance after updating
		  [--verbose]                              # Enable verbose logging
		  [--official]                             # For official use.  Send emails, etc.
		  [--exclude-broker]                       # Exclude broker tests
		  [--exclude-runtime]                      # Exclude runtime tests
		  [--exclude-site]                         # Exclude site tests
		  [--exclude-rhc]                          # Exclude rhc tests
		  [--include-web]                          # Include running Selenium tests
		  [--include-coverage]                     # Include coverage analysis on unit tests
		  [--include-extended=INCLUDE_EXTENDED]    # Include extended tests
		  [--base-image-filter=BASE_IMAGE_FILTER]  # Filter for the base image to use EX: devenv-base_*
		  [--region=REGION]                        # Amazon region override (default us-east-1)
		  [--install-from-source]                  # Indicates whether to build based off origin/master
		  [--install-from-local-source]            # Indicates whether to build based on your local source
		  [--install-required-packages]            # Create an instance with all the packages required by OpenShift
		  [--skip-verify]                          # Skip running tests to verify the build
		  [--instance-type=INSTANCE_TYPE]          # Amazon machine type override (default c1.medium)

  * ./build/devenv launch [NAME]

	Launches the latest DevEnv instance, tagging with NAME

		Options:
		  [--verifier]                     # Add verifier functionality (private IP setup and local tests)
		  [--branch=BRANCH]                # Launch a devenv image from a particular branch
		                                   # Default: master
		  [--verbose]                      # Enable verbose logging
		  [--express-server]               # Set as express server in express.conf
		  [--ssh-config-verifier]          # Set as verifier in .ssh/config
		  [--instance-type=INSTANCE_TYPE]  # Amazon machine type override (default 'm1.large')
		  [--region=REGION]                # Amazon region override (default us-east-1)
		  [--image-name=IMAGE_NAME]        # AMI ID or DEVENV name to launch
		  [--v2-carts]                     # Launch Origin AMI with v2 cartridges enabled

  * ./build/devenv sanity_check [TAG]

	Runs a set of sanity check tests on a tagged instance

		Options:
		  [--verbose]        # Enable verbose logging
		  [--region=REGION]  # Amazon region override (default us-east-1)

  * ./build/devenv terminate [TAG]

	Terminates the instance with the specified tag

		Options:
		  [--verbose]        # Enable verbose logging
		  [--region=REGION]  # Amazon region override (default us-east-1)

  * ./build/devenv test [TAG]

	Runs the tests on a tagged instance and downloads the results

		Options:
		  [--terminate]                          # Terminate the instance when finished
		  [--verbose]                            # Enable verbose logging
		  [--official]                           # For official use.  Send emails, etc.
		  [--exclude-broker]                     # Exclude broker tests
		  [--exclude-runtime]                    # Exclude runtime tests
		  [--exclude-site]                       # Exclude site tests
		  [--exclude-rhc]                        # Exclude rhc tests
		  [--include-cucumber=INCLUDE_CUCUMBER]  # Include a specific cucumber test (verify, internal, node, api, etc)
		  [--include-coverage]                   # Include coverage analysis on unit tests
		  [--include-extended=INCLUDE_EXTENDED]  # Include extended tests
		  [--disable-charlie]                    # Disable idle shutdown timer on dev instance (charlie)
		  [--mcollective-logs]                   # Don't allow mcollective logs to be deleted on rotation
		  [--profile-broker]                     # Enable profiling code on broker
		  [--include-web]                        # Include running Selenium tests
		  [--sauce-username=SAUCE_USERNAME]      # Sauce Labs username
		  [--sauce-access-key=SAUCE_ACCESS_KEY]  # Sauce Labs access key
		  [--sauce-overage]                      # Run Sauce Labs tests even if we are over our monthly minute quota
		  [--region=REGION]                      # Amazon region override (default us-east-1)

  * ./build/devenv sync [NAME]

	Synchronize a local git repo with a remote DevEnv instance. NAME should be ssh resolvable.

		Options:
		  [--tag]             # NAME is an Amazon tag
		  [--verbose]         # Enable verbose logging
		  [--skip-build]      # Indicator to skip the rpm build/install
		  [--clean-metadata]  # Cleans metadata before running yum commands
		  [--region=REGION]   # Amazon region override (default us-east-1)

### Local build and test options
	
  * ./build/devenv clone_addtl_repos [BRANCH]

	Clones any additional repos not including this repo and any other repos that extend these dev tools
	
		Options:
		  [--replace]  # Replace the addtl repos if the already exist

  * ./build/devenv install_local_client

	Builds and installs the local client rpm (uses sudo)
	
		Options:
		  [--verbose]  # Enable verbose logging

  * ./build/devenv install_required_packages

	Install the packages required, as specified in the spec files
	
		Options:
		  [--verbose]  # Enable verbose logging

  * ./build/devenv local_build

	Builds and installs all packages locally
	
		Options:
		  [--verbose]          # Enable verbose logging
		  [--clean-packages]   # Erase existing packages before install?
		  [--update-packages]  # Run yum update before install?
		  [--incremental]      # Build only the changed packages

  devenv update                     # Update current instance by installing RPMs from local git tree

		Options:
		  [--include-stale]           # Include packages that have been tagged but not synced to the repo
		  [--verbose]                 # Enable verbose logging
		  [--retry-failure-with-tag]  # If a package fails to build, tag it and retry the build.
		                              # Default: true


### Fedora 17 Remix

  * ./build/devenv build_livecd

	Build a Feodra 17 remix CD with OpenShift Origin installed and configured on it


## Related repositories

 * [Origin-Server](https://github.com/openshift/origin-server) Origin-server contains the core server components of the OpenShift service released under the [OpenShift Origin source
project](https://openshift.redhat.com/community/open-source).
 * [Origin Community Cartridges](https://github.com/openshift/origin-community-cartridges) Collection of OpenShift Origin cartridges contributed by community members.
 * [RHC](https://github.com/openshift/rhc) The OpenShift command line tools allow you to manage your OpenShift applications from the command line.
 * [puppet-openshift_origin](https://github.com/openshift/puppet-openshift_origin) Puppet scripts to install and configure OpenShift Origin on Fedora 17.

## Contributing

Visit the [OpenShift Origin Open Source
page](https://openshift.redhat.com/community/open-source) for more
information on the community process and how you can get involved.


## Copyright

OpenShift Origin, except where otherwise noted, is released under the
[Apache License 2.0](http://www.apache.org/licenses/LICENSE-2.0.html).
See the LICENSE file located in each component directory.

## Export Control

This software distribution includes cryptographic software that is
subject to the U.S. Export Administration Regulations (the “*EAR*”) and
other U.S. and foreign laws and may not be exported, re-exported or
transferred (a) to any country listed in Country Group E:1 in Supplement
No. 1 to part 740 of the EAR (currently, Cuba, Iran, North Korea, Sudan,
and Syria); (b) to any prohibited destination or to any end user who has
been prohibited from participating in U.S. export transactions by any
federal agency of the U.S. government; or (c) for use in connection with
the design, development or production of nuclear, chemical or biological
weapons, or rocket systems, space launch vehicles, or sounding rockets,
or unmanned air vehicle systems. You may not download this software or
technical information if you are located in one of these countries or
otherwise subject to these restrictions. You may not provide this
software or technical information to individuals or entities located in
one of these countries or otherwise subject to these restrictions. You
are also responsible for compliance with foreign law requirements
applicable to the import, export and use of this software and technical
information.