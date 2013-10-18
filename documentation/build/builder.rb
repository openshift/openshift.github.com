#!/usr/bin/env ruby

$: << File.expand_path(File.dirname(__FILE__))

require 'rubygems'
require 'thor'
require 'fileutils'
require 'lib/openshift'
require 'pp'
require 'yaml'

include FileUtils

module OpenShift
  class Builder < Thor
    include OpenShift::BuilderHelper

    no_tasks do
      def post_launch_setup(hostname,options)
        # Child classes can override, if required
      end

    end
    
    desc "find_and_build_specs", "Builds all non ignored specs in the current directory", :hide => true
    method_option :base_os, :default => nil, :desc => "Operating system for Origin (fedora or rhel)"
    method_option :ssh_user, :type => :string, :default => "root", :desc => "User to use when ssh'ing to build maching"
    def find_and_build_specs
      def_constants(guess_os(options.base_os))
      
      packages = get_packages(false, true).values
      buildable = packages.select{ |p| not IGNORE_PACKAGES.include? p.name }.select do |p|
        Dir.chdir(p.dir) { system "git tag | grep '#{p.name}' 2>&1 1>/dev/null" }.tap do |r|
          puts "\n\nSkipping '#{p.name}' in '#{p.dir}' since it is not tagged.\n" unless r
        end
      end

      # packages not in source
      installed = buildable.map(&:build_requires).flatten(1).uniq.sort - buildable

      phases = []
      while not buildable.empty?
        # separate packages that depend on other packages
        installable, has_dependencies = buildable.partition do |p|
          (p.build_requires & buildable).empty? #.any?{ |req| buildable.any?{ |b| req === b } }
        end
        begin
          installable, is_dependent = installable.partition do |p|
            (p.build_requires & has_dependencies).empty? #.any?{ |name| has_dependencies.any?{ |b| name == b.name } }
          end
          has_dependencies.concat(is_dependent)
        end while not is_dependent.empty?

        raise "The packages remaining to install #{dependencies.inspect} have mutual dependencies" if installable.empty?

        phases << installable

        buildable = has_dependencies
      end

      prereqs = installed.map(&:yum_name) - SKIP_PREREQ_PACKAGES
      puts "\n\nExcluded prereqs\n  #{SKIP_PREREQ_PACKAGES.join("\n  ")}" unless SKIP_PREREQ_PACKAGES.empty?
      puts "\n\nInstalling all prereqs\n  #{prereqs.join("\n  ")}"
      raise "Unable to install prerequisite packages" unless system "yum install -y #{prereqs.join(' ')}"

      prereqs = (phases[1..-1] || []).flatten(1).map(&:build_requires).flatten(1).uniq.sort - installed
      puts "\nPackages that are prereqs for later phases\n  #{prereqs.join("\n  ")}"

      phases.each_with_index do |phase,i|
        puts "\n#{'='*60}\n\nBuilding phase #{i+1} packages"
        phase.sort.each do |package|

          gem_build = package.spec_file =~ /^Source0(.+).gem(\s*)$/

          if gem_build.nil?
            tito_cmd = "tito build --rpm --test"
          else
            tito_cmd = "tito build --builder=tito.builder.GemBuilder --rpm --test"
          end

          Dir.chdir(package.dir) do
            puts "\n#{'-'*60}"
            raise "Unable to build #{package.name}" unless system tito_cmd
            if prereqs.include? package
              puts "\n    Installing..."
              #FileUtils.rm_rf "/tmp/tito/**"
              raise "Unable to install package #{package.name}" unless system("rpm -Uvh --force /tmp/tito/noarch/#{package}*.rpm")
            end
          end
        end
      end
    end

    desc "install_required_packages", "Install the packages required, as specified in the spec files"
    method_option :base_os, :default => nil, :desc => "Operating system for Origin (fedora or rhel)"
    method_option :verbose, :type => :boolean, :desc => "Enable verbose logging"
    method_option :ssh_user, :type => :string, :default => "root", :desc => "User to use when ssh'ing to build maching"
    def install_required_packages
      def_constants(guess_os(options.base_os))

      options.verbose? ? log.level = Logger::DEBUG : log.level = Logger::ERROR
      packages = get_required_packages
      packages.gsub!(">= %{rubyabi}", "")
      if guess_os(options.base_os) == "fedora-19"
        packages.gsub!("ruby193-", "")
      end

      unless run("su -c \"yum install -y --skip-broken --exclude=\\\"java-1.7.0-openjdk-*\\\" --exclude=\\\"java-1.6.0-openjdk-*\\\" #{packages} 2>&1\"")
        exit 1
      end
    end

    desc "build NAME BUILD_NUM", "Build a new devenv AMI with the given NAME"
    method_option :base_os, :default => nil, :desc => "Operating system for Origin (fedora or rhel)"
    method_option :register, :type => :boolean, :desc => "Register the instance"
    method_option :terminate, :type => :boolean, :desc => "Terminate the instance on exit"
    method_option :branch, :default => "master", :desc => "Build instance off the specified branch"
    method_option :yum_repo, :default => "candidate", :desc => "Build instance off the specified yum repository"
    method_option :reboot, :type => :boolean, :desc => "Reboot the instance after updating"
    method_option :verbose, :type => :boolean, :desc => "Enable verbose logging"
    method_option :official, :type => :boolean, :desc => "For official use.  Send emails, etc."
    method_option :exclude_broker, :type => :boolean, :desc => "Exclude broker tests"
    method_option :exclude_runtime, :type => :boolean, :desc => "Exclude runtime tests"
    method_option :exclude_site, :type => :boolean, :desc => "Exclude site tests"
    method_option :exclude_rhc, :type => :boolean, :desc => "Exclude rhc tests"
    method_option :include_extended, :required => false, :desc => "Include extended tests"
    method_option :base_image_filter, :desc => "Filter for the base image to use EX: devenv-base_*"
    method_option :region, :required => false, :desc => "Amazon region override (default us-east-1)"
    method_option :install_from_source, :type => :boolean, :desc => "Indicates whether to build based off origin/master"
    method_option :install_from_local_source, :type => :boolean, :desc => "Indicates whether to build based on your local source"
    method_option :install_required_packages, :type => :boolean, :desc => "Create an instance with all the packages required by OpenShift"
    method_option :skip_verify, :type => :boolean, :desc => "Skip running tests to verify the build"
    method_option :instance_type, :required => false, :desc => "Amazon machine type override (default c1.medium)"
    method_option :extra_rpm_dir, :required => false, :dessc => "Directory containing extra rpms to be installed"
    method_option :disable_selinux, :required => false, :default => false, :type => :boolean, :dessc => "Directory containing extra rpms to be installed"
    method_option :ssh_user, :type => :string, :default => "root", :desc => "User to use when ssh'ing to build maching"
    def build(name, build_num)
      options.verbose? ? log.level = Logger::DEBUG : log.level = Logger::ERROR
      def_constants(guess_os(options.base_os))

      # Override the machine type to launch if necessary
      $amz_options[:instance_type] = options[:instance_type] if options[:instance_type]
  
      # Establish a new connection
      conn = connect(options.region)

      image = nil
      if options.install_required_packages?
        # Create a new builder instance
        if (options.region?nil)
          image = conn.images[AMI["us-east-1"]]
        elsif AMI[options.region].nil?
          puts "No AMI specified for region:" + options.region
          exit 1
        else
          image = conn.images[AMI[options.region]]
        end
      else
        # Get the latest devenv base image and create a new instance
        filter = nil
        if options.base_image_filter
          filter = options.base_image_filter
        else
          filter = devenv_base_branch_wildcard(options.branch)
        end
        image = get_latest_ami(conn, filter)
      end

      build_impl(name, build_num, image, conn, options)
    end

    desc "update", "Update current instance by installing RPMs from local git tree"
    method_option :include_stale, :type => :boolean, :desc => "Include packages that have been tagged but not synced to the repo"
    method_option :verbose, :type => :boolean, :desc => "Enable verbose logging"
    method_option :retry_failure_with_tag, :type => :boolean, :default=>true, :desc => "If a package fails to build, tag it and retry the build."
    method_option :ssh_user, :type => :string, :default => "root", :desc => "User to use when ssh'ing to build maching"
    def update
      def_constants(guess_os())
      
      options.verbose? ? log.level = Logger::DEBUG : log.level = Logger::ERROR
      # Warn on uncommitted changes
      `git diff-index --quiet HEAD`
      puts "WARNING - Uncommitted repository changes" if $? != 0
    
      # Figure out what needs to be built - exclude devenv for syncs
      sync_dirs = get_sync_dirs
      sync_dirs = sync_dirs.sort_by{ |sync_dir| sync_dir[0] }.reverse
    
      sync_dirs.each do |sync_dir|
        package_name = sync_dir[0]
        build_dir = sync_dir[1]
        spec_file = sync_dir[2]
    
        if IGNORE_PACKAGES.include? package_name
          puts "Skipping #{package_name}"
          return
        else
          build_and_install(package_name, build_dir, spec_file, options)
        end
      end
    
      if options.include_stale?
        stale_dirs = get_stale_dirs
        stale_dirs.each do |stale_dir|
          package_name = stale_dir[0]
          build_dir = stale_dir[1]
          spec_file = stale_dir[2]
    
          if IGNORE_PACKAGES.include? package_name
            puts "Skipping #{package_name}"
            return
          else
            build_and_install(package_name, build_dir, spec_file, options)
          end
        end
      end
      restart_services
    end

    desc "sync NAME", "Synchronize a local git repo with a remote DevEnv instance.  NAME should be ssh resolvable."
    method_option :base_os, :default => nil, :desc => "Operating system for Origin (fedora or rhel)"
    method_option :tag, :type => :boolean, :desc => "NAME is an Amazon tag"
    method_option :verbose, :type => :boolean, :desc => "Enable verbose logging"
    method_option :skip_build, :type => :boolean, :desc => "Indicator to skip the rpm build/install"
    method_option :clean_metadata, :type => :boolean, :desc => "Cleans metadata before running yum commands"
    method_option :region, :required => false, :desc => "Amazon region override (default us-east-1)"
    method_option :ssh_user, :type => :string, :default => "root", :desc => "User to use when ssh'ing to build maching"
    def sync(name)
      def_constants(guess_os(options.base_os))
      
      options.verbose? ? log.level = Logger::DEBUG : log.level = Logger::ERROR
      sync_impl(name, options)
    end

    desc "terminate TAG", "Terminates the instance with the specified tag"
    method_option :base_os, :default => nil, :desc => "Operating system for Origin (fedora or rhel)"
    method_option :download_artifacts, :type => :boolean, :desc => "Download artifacts before terminating"    
    method_option :verbose, :type => :boolean, :desc => "Enable verbose logging"
    method_option :region, :required => false, :desc => "Amazon region override (default us-east-1)"
    method_option :ssh_user, :type => :string, :default => "root", :desc => "User to use when ssh'ing to build maching"
    def terminate(tag)
      def_constants(guess_os(options.base_os))
      options.verbose? ? log.level = Logger::DEBUG : log.level = Logger::ERROR
      conn = connect(options.region)
      instance = find_instance(conn, tag, true, false, options.ssh_user)
      if (defined? download_artifacts) && instance && (instance_status(instance) == :running) && options.download_artifacts?
        download_artifacts(instance.dns_name)
      end
      terminate_instance(instance, true) if instance
    end

    desc "update_ssh_config TAG", "Updates the verifier entry in the ssh config file with the dns info from tag"
    method_option :verbose, :type => :boolean, :desc => "Enable verbose logging"
    method_option :region, :required => false, :desc => "Amazon region override (default us-east-1)"
    def update_ssh_config(tag)
      options.verbose? ? log.level = Logger::DEBUG : log.level = Logger::ERROR
      conn = connect(options.region)
      instance = find_instance(conn, tag, true, false)
      update_ssh_config_verifier(instance)
    end

    desc "launch NAME", "Launches the latest DevEnv instance, tagging with NAME"
    method_option :base_os, :default => nil, :desc => "Operating system for Origin (fedora or rhel)"
    method_option :verifier, :type => :boolean, :desc => "Add verifier functionality (private IP setup and local tests)"
    method_option :branch, :default => "master", :desc => "Launch a devenv image from a particular branch"
    method_option :verbose, :type => :boolean, :desc => "Enable verbose logging"
    method_option :express_server, :type => :boolean, :desc => "Set as express server in express.conf"
    method_option :ssh_config_verifier, :type => :boolean, :desc => "Set as verifier in .ssh/config"
    method_option :instance_type, :required => false, :desc => "Amazon machine type override (default '#{TYPE}')"
    method_option :region, :required => false, :desc => "Amazon region override (default us-east-1)"
    method_option :image_name, :required => false, :desc => "AMI ID or DEVENV name to launch"
    method_option :ssh_user, :type => :string, :default => "root", :desc => "User to use when ssh'ing to build maching"
    def launch(name)
      options.verbose? ? log.level = Logger::DEBUG : log.level = Logger::ERROR
      def_constants(guess_os(options.base_os))
      ami = choose_ami_for_launch(options)

      # Override the machine type to launch if necessary
      $amz_options[:instance_type] = options[:instance_type] if options[:instance_type]

      if ami.nil?
        puts "No image name '#{options[:image_name]}' found!"
        exit(1)
      else
        puts "Launching latest instance #{ami.id} - #{ami.name}"
      end

      instance = launch_instance(ami, name, 1, options.ssh_user)
      hostname = instance.dns_name
      puts "Done"
      puts "Hostname: #{hostname}"

      puts "Sleeping for #{SLEEP_AFTER_LAUNCH} seconds to let node stabilize..."
      sleep SLEEP_AFTER_LAUNCH
      puts "Done"

      update_facts_impl(hostname)
      post_launch_setup(hostname,options)
      setup_verifier(hostname, options.branch) if options.verifier?

      validate_instance(hostname, 4)

      update_api_file(instance) if options.ssh_config_verifier?
      update_ssh_config_verifier(instance) if options.ssh_config_verifier?
      update_express_server(instance) if options.express_server?

      home_dir=File.join(ENV['HOME'], '.openshiftdev/home.d')
      if File.exists?(home_dir)
        Dir.glob(File.join(home_dir, '???*'), File::FNM_DOTMATCH).each {|file|
          puts "Installing ~/#{File.basename(file)}"
          scp_to(hostname, file, "~/", File.stat(file).mode, 10, options.ssh_user)
        }
      end

      puts "Public IP:       #{instance.public_ip_address}"
      puts "Public Hostname: #{hostname}"
      puts "Site URL:        https://#{hostname}"
      puts "Done"
    end

    desc "test TAG", "Runs the tests on a tagged instance and downloads the results"
    method_option :base_os, :default => nil, :desc => "Operating system for Origin (fedora or rhel)"
    method_option :terminate, :type => :boolean, :desc => "Terminate the instance when finished"
    method_option :verbose, :type => :boolean, :desc => "Enable verbose logging"
    method_option :official, :type => :boolean, :desc => "For official use.  Send emails, etc."
    method_option :exclude_broker, :type => :boolean, :desc => "Exclude broker tests"
    method_option :exclude_runtime, :type => :boolean, :desc => "Exclude runtime tests"
    method_option :exclude_site, :type => :boolean, :desc => "Exclude site tests"
    method_option :exclude_rhc, :type => :boolean, :desc => "Exclude rhc tests"
    method_option :include_cucumber, :required => false, :desc => "Include a specific cucumber test (verify, internal, node, api, etc)"
    method_option :include_extended, :required => false, :desc => "Include extended tests"
    method_option :disable_charlie, :type => :boolean, :desc=> "Disable idle shutdown timer on dev instance (charlie)"
    method_option :mcollective_logs, :type => :boolean, :desc=> "Don't allow mcollective logs to be deleted on rotation"
    method_option :profile_broker, :type => :boolean, :desc=> "Enable profiling code on broker"
    method_option :sauce_username, :required => false, :desc => "Sauce Labs username"
    method_option :sauce_access_key, :required => false, :desc => "Sauce Labs access key"
    method_option :sauce_overage, :type => :boolean, :desc => "Run Sauce Labs tests even if we are over our monthly minute quota"
    method_option :region, :required => false, :desc => "Amazon region override (default us-east-1)"
    method_option :ssh_user, :type => :string, :default => "root", :desc => "User to use when ssh'ing to build maching"
    def test(tag)
      options.verbose? ? log.level = Logger::DEBUG : log.level = Logger::ERROR
      def_constants(guess_os(options.base_os))
      conn = connect(options.region)
      instance = find_instance(conn, tag, true, true, options.ssh_user)
      raise "Could not find an instance that matches #{tag}" unless instance
      hostname = instance.dns_name

      test_impl(tag, hostname, instance, conn, options)
    end

    desc "sanity_check TAG", "Runs a set of sanity check tests on a tagged instance"
    method_option :base_os, :default => nil, :desc => "Operating system for Origin (fedora or rhel)"
    method_option :verbose, :type => :boolean, :desc => "Enable verbose logging"
    method_option :region, :required => false, :desc => "Amazon region override (default us-east-1)"
    method_option :ssh_user, :type => :string, :default => "root", :desc => "User to use when ssh'ing to build maching"
    def sanity_check(tag)
      options.verbose? ? log.level = Logger::DEBUG : log.level = Logger::ERROR
      def_constants(guess_os(options.base_os))

      conn = connect(options.region)
      instance = find_instance(conn, tag, true, true, options.ssh_user)
      raise "Could not find an instance that matches #{tag}" unless instance
      hostname = instance.dns_name

      sanity_check_impl(tag, hostname, instance, conn, options)
    end
    
    desc "print_hostname", "Print the hostname of a tagged instance"
    method_option :region, :required => false, :desc => "Amazon region override (default us-east-1)"
    method_option :ssh_user, :type => :string, :default => "root", :desc => "User to use when ssh'ing to build maching"
    def print_hostname(tag)
      log.level = Logger::ERROR
      conn = connect(options.region)
      instance = find_instance(conn, tag, true, true, options.ssh_user, true)
      raise "Could not find an instance that matches #{tag}" unless instance
      hostname = instance.dns_name
      print hostname
    end
    
    desc "clone_addtl_repos BRANCH", "Clones any additional repos not including this repo and any other repos that extend these dev tools"
    method_option :replace, :type => :boolean, :desc => "Replace the addtl repos if the already exist"
    def clone_addtl_repos(branch)
      git_clone_commands = "set -e\n "

      ADDTL_SIBLING_REPOS.each do |repo_name|
        repo_git_url = SIBLING_REPOS_GIT_URL[repo_name]
        git_clone_commands += "pushd ..\n"
        git_clone_commands += "if [ ! -d #{repo_name} ]; then\n" unless options.replace?
        git_clone_commands += "rm -rf #{repo_name}; git clone #{repo_git_url};\n"
        git_clone_commands += "fi\n" unless options.replace?
        git_clone_commands += "pushd #{repo_name}\n"
        git_clone_commands += "git checkout #{branch}\n"
        git_clone_commands += "popd\n"
        git_clone_commands += "popd\n"
      end
      unless run(git_clone_commands, :verbose => true)
        exit 1
      end
    end

    desc "install_local_client", "Builds and installs the local client rpm (uses sudo)"
    method_option :verbose, :type => :boolean, :desc => "Enable verbose logging"
    def install_local_client
      options.verbose? ? log.level = Logger::DEBUG : log.level = Logger::ERROR

      if File.exists?('../rhc')
        inside('../rhc') do
          begin
            temp_commit

            puts "building rhc..."
            `tito build --rpm --test`
            puts "installing rhc..."
            `sudo rpm -Uvh --force /tmp/tito/noarch/rhc-*; rm -rf /tmp/tito; mkdir -p /tmp/tito`

          ensure
            reset_temp_commit
          end

          puts "Done"
        end
      else
        puts "Couldn't find ../rhc."
      end
    end

    no_tasks do
      def choose_ami_for_launch(options)
        # Get the latest devenv image and create a new instance
        conn = connect(options.region)
        filter = choose_filter_for_launch_ami(options)
        if options[:image_name]
          filter = options[:image_name]
          ami = get_specific_ami(conn, filter)
        else
          ami = get_latest_ami(conn, filter)
        end
        ami
      end

      def choose_filter_for_launch_ami(options)
        devenv_branch_wildcard(options.branch)
      end
    end #no_tasks
  end #class
end #module
