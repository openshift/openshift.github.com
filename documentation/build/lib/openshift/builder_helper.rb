#!/usr/bin/env ruby

require 'rubygems'
require 'thor'
require 'fileutils'
require 'pp'
require 'yaml'

include FileUtils

# we will need ssh with some different options for git clones
GIT_SSH_PATH=File.expand_path(File.dirname(__FILE__)) + "/ssh-override"

module OpenShift
  module BuilderHelper
    include Thor::Actions
    include OpenShift::Tito
    include OpenShift::SSH
    include OpenShift::Amazon

    @@SSH_TIMEOUT = 4800
    @@SSH_TIMEOUT_OVERRIDES = { "benchmark" => 172800 }

    # Get the hostname from a tag lookup or assume it's SSH accessible directly
    # Only look for a tag if the --tag option is specified
    def get_host_by_name_or_tag(name, options=nil, user="root")
      return name unless options && options.tag?

      instance = find_instance(connect(options.region), name, true, true, user)
      if not instance.nil?
        return instance.dns_name
      else
        puts "Unable to find instance with tag: #{name}"
        exit 1
      end
    end

    def build_and_install(package_name, build_dir, spec_file, options)
      remove_dir '/tmp/tito/'
      FileUtils.mkdir_p '/tmp/tito/'
      puts "Building in #{build_dir}"
      spec_file = File.expand_path(spec_file)
      # Check if we need to use the GemBuilder with tito
      check_gem_source = File.readlines(spec_file).select { |line|
                                            line =~ /^Source0(.+).gem(\s*)$/ }
      if !check_gem_source.empty?
        tito_cmd = "tito build --builder=tito.builder.GemBuilder --rpm --test"
      else
        tito_cmd = "tito build --rpm --test"
      end

      inside(File.expand_path("#{build_dir}", File.dirname(File.dirname(File.dirname(File.dirname(__FILE__)))))) do
        # Build and install the RPM's locally
        unless run(tito_cmd, :verbose => options.verbose?)
          package = Package.new(spec_file, File.dirname(spec_file))
          package_name = package.name
          ignore_packages = get_ignore_packages
          packages = get_packages
          required_packages_str = ''
          unless ignore_packages.include?(package_name)
            package.build_requires.each do |r_package|
              required_packages_str += " \\\"#{r_package.yum_name_with_version}\\\"" unless packages.include?(r_package.name)
            end
          end
          run("sudo bash -c \"yum install -y --skip-broken #{required_packages_str} 2>&1\"") unless required_packages_str.empty?

          if required_packages_str.empty? || !run(tito_cmd, :verbose => options.verbose?)
            if options.retry_failure_with_tag
              # Tag to trick tito to build
              commit_id = `git log --pretty=format:%%H --max-count=1 %s" % .`
              spec_file_name = File.basename(spec_file)
              version = get_version(spec_file_name)
              next_version = next_tito_version(version, commit_id)
              puts "current spec file version #{version} next version #{next_version}"
              unless run("tito tag --accept-auto-changelog --use-version='#{next_version}'; #{tito_cmd}", :verbose => options.verbose?)
                FileUtils.rm_rf '/tmp/devenv/sync/'
                exit 1
              end
            else
              puts "Package #{package_name} failed to build."
            end
          end
        end
        Dir.glob('/tmp/tito/x86_64/*.rpm').each {|file|
          FileUtils.mkdir_p "/tmp/tito/noarch/"
          FileUtils.mv file, "/tmp/tito/noarch/"
        }
        unless run("rpm -Uvh --force /tmp/tito/noarch/*.rpm", :verbose => options.verbose?)
          unless run("rpm -e --justdb --nodeps #{package_name}; yum install -y /tmp/tito/noarch/*.rpm", :verbose => options.verbose?)
            FileUtils.rm_rf '/tmp/devenv/sync/'
            exit 1
          end
        end
        if build_dir =~ /\/cartridges\/openshift-origin-cartridge-(.*)/ || build_dir =~ /\/cartridges\/(.*)/
          short_cart_name = $1
          cart_install_dir = "/usr/libexec/openshift/cartridges/#{short_cart_name}"
          if File.exists? cart_install_dir
            unless run("oo-admin-cartridge --action install --source #{cart_install_dir}", :verbose => options.verbose?)
              FileUtils.rm_rf '/tmp/devenv/sync/'
              exit 1
            end
          end
        end
      end
    end

    def update_remote_tests(hostname, branch=nil, repo_parent_dir="/root", user="root")
      puts "Updating remote tests..."
      git_archive_commands = ''
      SIBLING_REPOS.each do |repo_name, repo_dirs|
        repo_dir = "#{repo_parent_dir}/#{repo_name}-bare"
        git_archive_commands += "pushd #{repo_dir} > /dev/null; git archive --prefix openshift-test/#{::OPENSHIFT_ARCHIVE_DIR_MAP[repo_name] || ''} --format=tar #{branch ? branch : 'HEAD'} | (cd #{repo_parent_dir} && tar --warning=no-timestamp -xf -); popd > /dev/null; "
      end

      output, exit_code = ssh(hostname, %{
set -e;
sudo bash -c \"rm -rf #{repo_parent_dir}/openshift-test\"
#{git_archive_commands}
sudo bash -c \"mkdir -p /tmp/rhc/junit\"
}, 120, true, 4, user)

      if exit_code != 0
        exit 1
      end

      update_cucumber_tests(hostname, repo_parent_dir, user)
      puts "Done"
    end

    def scp_remote_tests(hostname, repo_parent_dir="/root", user="root")
      init_repos(hostname, true, nil, repo_parent_dir, user)
      sync_repos(hostname, repo_parent_dir, user)
      update_remote_tests(hostname, nil, repo_parent_dir, user)
    end

    def sync_repos(hostname, remote_repo_parent_dir="/root", sshuser="root")
      SIBLING_REPOS.each do |repo_name, repo_dirs|
        repo_dirs.each do |repo_dir|
          break if sync_sibling_repo(repo_name, repo_dir, hostname, remote_repo_parent_dir, sshuser)
        end
      end
    end

    def sync_repo(repo_name, hostname, remote_repo_parent_dir="/root", ssh_user="root", verbose=false)
      begin
        temp_commit

        # Get the current branch
        branch = get_branch

        puts "Synchronizing local changes from branch #{branch} for repo #{repo_name} from #{File.basename(FileUtils.pwd)}..."

        init_repos(hostname, false, repo_name, remote_repo_parent_dir, ssh_user)

        exitcode = run(<<-"SHELL", :verbose => verbose)
          #######
          # Start shell code
          export GIT_SSH=#{GIT_SSH_PATH}
          #{branch == 'origin/master' ? "git push -q #{ssh_user}@#{hostname}:#{remote_repo_parent_dir}/#{repo_name}-bare master:master --tags --force; " : ''}
          git push -q #{ssh_user}@#{hostname}:#{remote_repo_parent_dir}/#{repo_name}-bare #{branch}:master --tags --force

          #######
          # End shell code
          SHELL

        puts "Done"
      ensure
        reset_temp_commit
      end
    end

    def sync_sibling_repo(repo_name, repo_dir, hostname, remote_repo_parent_dir="/root", ssh_user="root")
      exists = File.exists?(repo_dir)
      inside(repo_dir) do
        sync_repo(repo_name, hostname, remote_repo_parent_dir, ssh_user)
      end if exists
      exists
    end

    def update_test_bundle(hostname, user, *dirs)
      cmd = ""
      dirs.each do |dir|
        cmd += "cd ~/openshift-test/#{dir}; rm Gemfile.lock; bundle install --local; touch Gemfile.lock;\n"
      end
      ssh(hostname, cmd, 60, false, 1, user)
    end

    # clones origin-server/rhc over to remote;
    # returns command to run remotely for cloning to standard working dirs,
    # plus the names of those working dirs
    def sync_available_sibling_repos(hostname, remote_repo_parent_dir="/root", ssh_user="root")
      working_dirs = ''
      clone_commands = ''
      SIBLING_REPOS.each do |repo_name, repo_dirs|
        repo_dirs.each do |repo_dir|

          if sync_sibling_repo(repo_name, repo_dir, hostname, remote_repo_parent_dir, ssh_user)
            working_dirs += "#{repo_name} "
            clone_commands += "git clone #{repo_name}-bare #{repo_name}; "
            break # just need the first repo found
          end
        end
      end
      return clone_commands, working_dirs
    end

    def repo_clone_commands(hostname)
      clone_commands = ''
      SIBLING_REPOS.each_key do |repo_name|
        clone_commands += "git clone #{repo_name}-bare #{repo_name}; "
      end
      clone_commands
    end

    def init_repos(hostname, replace=true, repo=nil, remote_repo_parent_dir="/root", ssh_user="root")
      git_clone_commands = ''

      SIBLING_REPOS.each do |repo_name, repo_dirs|
        if repo.nil? or repo == repo_name
          repo_git_url = SIBLING_REPOS_GIT_URL[repo_name]
          git_clone_commands += "if [ ! -d #{remote_repo_parent_dir}/#{repo_name}-bare ]; then\n" unless replace
          git_clone_commands += "rm -rf #{remote_repo_parent_dir}/#{repo_name}; git clone --bare #{repo_git_url} #{remote_repo_parent_dir}/#{repo_name}-bare;\n"
          git_clone_commands += "fi\n" unless replace
        end
      end
      ssh(hostname, git_clone_commands, 240, false, 10, ssh_user)
    end

    def get_required_packages
      required_packages_str = ""
      packages = get_sorted_package_names
      ignore_packages = get_ignore_packages

      SIBLING_REPOS.each do |repo_name, repo_dirs|
        repo_dirs.each do |repo_dir|
          exists = File.exists?(repo_dir)
          inside(repo_dir) do
            spec_file_list = `find -name *.spec`.split("\n")
            spec_file_list.each do |spec_file|
              package = Package.new(spec_file, File.dirname(spec_file))
              package_name = package.name
              unless ignore_packages.include?(package.name)
                required_packages = package.build_requires + package.requires
                required_packages.each do |r_package|
                  required_packages_str += " \\\"#{r_package.yum_name_with_version}\\\"" unless packages.include?(r_package.name)
                end
              end
            end
          end if exists
        end
      end
      required_packages_str
    end

    def get_sorted_package_names
      packages = get_packages(true)
      packages_str = ""
      packages.keys.sort.each do |package_name|
        packages_str += " #{package_name}"
      end
      packages_str
    end

    def get_ignore_packages(include_unmodified=false)
      packages_str = ""
      IGNORE_PACKAGES.each do |package_name|
        packages_str += " #{package_name}"
      end

      if options.include_unmodified?
        build_dirs = get_build_dirs

        all_packages = get_packages
        build_dirs.each do |build_info|
          package_name = build_info[0]
          all_packages.delete(package_name)
        end

        all_packages.keys.each do |package_name|
          packages_str += " #{package_name}"
        end
      end

      packages_str
    end

    def temp_commit
      # Warn on uncommitted changes
      `git diff-index --quiet HEAD`

      if $? != 0
        # Perform a temporary commit
        puts "Creating temporary commit to build"

        begin
          `git commit -m "Temporary commit #1 - index changes"`
        ensure
          (@temp_commit ||= []).push("git reset --soft HEAD^") if $? == 0
        end

        begin
          `git commit -a -m "Temporary commit #2 - non-index changes"`
        ensure
          (@temp_commit ||= []).push("git reset --mixed HEAD^") if $? == 0
        end

        puts @temp_commit ? "No-op" : "Done"
      end
    end

    def reset_temp_commit
      if @temp_commit
        puts "Undoing temporary commit..."
        while undo = @temp_commit.pop
          `#{undo}`
        end
        @temp_commit = nil
        puts "Done."
      end
    end

    def mcollective_logs(hostname)
      puts "Keep all mcollective logs on remote instance: #{hostname}"
      ssh(hostname, "echo keeplogs=9999 >> #{SCL_ROOT}/etc/mcollective/server.cfg", 240)
      ssh(hostname, "/sbin/service #{SCL_PREFIX}mcollective restart", 240)
    end

    def update_api_file(instance)
      public_ip = instance.dns_name
      external_config = "~/.openshift/console.conf"
      config_file = File.expand_path(external_config)

      Dir.mkdir(File.expand_path('~/.openshift')) rescue nil

      if not FileTest.exists?(config_file)
        puts "File '#{external_config}' does not exist, creating..."
        system("touch #{external_config}")
        File.open(config_file, 'w') do |f| f.write(<<-END
BROKER_URL=https://#{public_ip}/broker/rest
DOMAIN_SUFFIX=dev.rhcloud.com
# Uncomment the next line to set a proxy URL for the broker
# BROKER_PROXY_URL=
          END
          )
        end

      else
        puts "Updating ~/.openshift/console.conf with public ip = #{public_ip}"
        s = IO.read(config_file)
        s.gsub!(%r[^BROKER_URL=\s*https://[^/]+/broker/rest$]m, "BROKER_URL=https://#{public_ip}/broker/rest")
        File.open(config_file, 'w'){ |f| f.write(s) }
      end
    end

    def update_ssh_config_verifier(instance)
      public_ip = instance.dns_name
      ssh_config = "~/.ssh/config"
      pem_file = File.expand_path("~/.ssh/libra.pem")
      if not File.exist?(pem_file)
        # copy it from local repo
        cmd = "cp misc/libra.pem #{pem_file}"
        puts cmd
        system(cmd)
        system("chmod 600 #{pem_file}")
      end
      config_file = File.expand_path(ssh_config)

      config_template = <<END
Host verifier
  HostName 10.1.1.1
  User      root
  IdentityFile ~/.ssh/libra.pem
END

      if not FileTest.exists?(config_file)
        puts "File '#{ssh_config}' does not exists, creating..."
        system("touch #{ssh_config}")
        cmd = "chmod 600 #{ssh_config}"
        system(cmd)
        file_mode = 'w'
        File.open(config_file, file_mode) { |f| f.write(config_template) }
      else
        if not system("grep -n 'Host verifier' #{config_file}")
          file_mode = 'a'
          File.open(config_file, file_mode) { |f| f.write(config_template) }
        end

      end

      line_num = `grep -n 'Host verifier' ~/.ssh/config`.chomp.split(':')[0]
      puts "Updating ~/.ssh/config verifier entry with public ip = #{public_ip}"
      (1..4).each do |i|
        `sed -i -e '#{line_num.to_i + i}s,HostName.*,HostName #{public_ip},' ~/.ssh/config`
      end
    end

    def update_express_server(instance)
      public_ip = instance.dns_name
      puts "Updating ~/.openshift/express.conf libra_server entry with public ip = #{public_ip}"
      `sed -i -e 's,^libra_server.*,libra_server=#{public_ip},' ~/.openshift/express.conf`
    end

    def repo_path(dir='')
      File.expand_path("../#{dir}", File.dirname(__FILE__))
    end

    def run_ssh(hostname, title, cmd, timeout=@@SSH_TIMEOUT, ssh_user="root")
      output, code = ssh(hostname, cmd, timeout, true, 1, ssh_user)
      puts <<-eos


          -----------------------------------------------------------
                      Begin Output From #{title} Tests
          -----------------------------------------------------------

# #{cmd}

#{output}

          -----------------------------------------------------------
                       End Output From #{title} Tests
          -----------------------------------------------------------


      eos
      return output, code
    end

    def reboot(instance)
      print "Rebooting instance to apply new kernel..."
      instance.reboot
      puts "Done"
    end

    def reset_test_dir(hostname, backup=false, ssh_user="root")
      ssh(hostname, %{
rm -rf /root/openshift-test/*/test/reports/*
cat<<EOF > /tmp/reset_test_dir.sh
if [ -d /tmp/rhc ]
then
    if #{backup}
    then
        if \\\$(ls /tmp/rhc/run_* > /dev/null 2>&1)
        then
            rm -rf /tmp/rhc_previous_runs
            mkdir -p /tmp/rhc_previous_runs
            mv /tmp/rhc/run_* /tmp/rhc_previous_runs
        fi
        if \\\$(ls /tmp/rhc/* > /dev/null 2>&1)
        then
            for i in {1..100}
            do
                if ! [ -d /tmp/rhc_previous_runs/run_\\\$i ]
                then
                    mkdir -p /tmp/rhc_previous_runs/run_\\\$i
                    mv /tmp/rhc/* /tmp/rhc_previous_runs/run_\\\$i
                    mkdir -p /tmp/rhc/cucumber_results/
                    mv /tmp/rhc_previous_runs/run_\\\$i/cucumber_results/*.xml /tmp/rhc/cucumber_results/
                    break
                fi
            done
        fi
        if \\\$(ls /tmp/rhc_previous_runs/run_* > /dev/null 2>&1)
        then
            mv /tmp/rhc_previous_runs/run_* /tmp/rhc/
            rm -rf /tmp/rhc_previous_runs
        fi
    else
        rm -rf /tmp/rhc
    fi
fi
mkdir -p /tmp/rhc/junit
EOF
chmod +x /tmp/reset_test_dir.sh
}, 120, true, 1, ssh_user)
      ssh(hostname, "sudo bash -c '/tmp/reset_test_dir.sh'" , 120, true, 1, ssh_user)
      ssh(hostname, "sudo bash -c 'rm -rf /var/www/openshift/broker/tmp/cache/*'" , 120, true, 1, ssh_user)
    end

    def devenv_branch_wildcard(branch)
      wildcard = nil
      if branch == 'master'
        wildcard = "#{DEVENV_NAME}_*"
      else
        wildcard = "#{DEVENV_NAME}-#{branch}_*"
      end
      wildcard
    end

    def devenv_base_branch_wildcard(branch)
      wildcard = nil
      if branch == 'master'
        wildcard = "#{DEVENV_NAME}-base_*"
      else
        wildcard = "#{DEVENV_NAME}-#{branch}-base_*"
      end
      wildcard
    end

    def print_highlighted_output(title, out)
      puts
      puts "------------------ Begin #{title} ------------------------"
      puts out
      puts "------------------- End #{title} -------------------------"
      puts
    end

    def print_and_exit(ret, out)
      if ret != 0
        puts "Exiting with error code #{ret}"
        puts "Output: #{out}"
        exit ret
      end
    end

    def run_tests_with_retry(test_queues, hostname, ssh_user="root")
      test_run_success = false
      (1..3).each do |retry_cnt|
        print "Test run ##{retry_cnt}\n\n\n"
        failure_queue = run_tests(test_queues, hostname, ssh_user)
        if failure_queue.empty?
          test_run_success = true
          break
        elsif retry_cnt < 3
          reset_test_dir(hostname, true, ssh_user)
        end
        test_queues = [failure_queue]
      end
      exit 1 unless test_run_success
    end

    def run_tests(test_queues, hostname, ssh_user)
      threads = []
      failures = []

      test_queues.each do |tqueue|
        threads << Thread.new do
          test_queue = tqueue
          start_time = Time.new
          test_queue.each do |test|
            output, exit_code = run_ssh(hostname, test[:title], test[:command], test[:options][:timeout], ssh_user)
            test[:output]  = output
            test[:exit_code]  = exit_code
            test[:success] = exit_code == 0
            test[:completed] = true

            still_running_tests = test_queues.map do |q|
              q.select{ |t| t[:completed] != true }
            end

            if still_running_tests.length > 0
              mins, secs = (Time.new - start_time).abs.divmod(60)
              puts "Still Running Tests (#{mins}m #{secs.to_i}s):"
              still_running_tests.each_index do |q_idx|
                puts "\t Queue #{q_idx}:"
                print still_running_tests[q_idx].map{ |t| "\t\t#{t[:title]}" }.join("\n"), "\n"
              end
              puts "\n\n\n"
            end
          end
        end
      end

      threads.each { |t| t.join }

      failures = test_queues.map{ |q| q.select{ |t| t[:success] == false }}
      failures.flatten!
      retry_queue = []
      if failures.length > 0
        idle_all_gears(hostname)
        print "Failures\n"
        print failures.map{ |f| f[:title] }.join("\n")
        puts "\n\n\n"

        #process failures
        failures.each do |failed_test|
          if failed_test[:options].has_key?(:cucumber_rerun_file)
            retry_queue << build_cucumber_command(failed_test[:title], [], failed_test[:options][:env],
                                                  failed_test[:options][:cucumber_rerun_file],
                                                  failed_test[:options][:test_dir],
                                                  "*.feature",
                                                  failed_test[:options][:require_gemfile_dir],
                                                  failed_test[:options][:other_outputs])
          elsif failed_test[:output] =~ /cucumber openshift-test\/tests\/.*\.feature:\d+/
            output.lines.each do |line|
              if line =~ /cucumber openshift-test\/tests\/(.*\.feature):(\d+)/
                test = $1
                scenario = $2
                if failed_test[:options][:retry_indivigually]
                  retry_queue << build_cucumber_command(failed_test[:title], [], failed_test[:options][:env],
                                                        failed_test[:options][:cucumber_rerun_file],
                                                        failed_test[:options][:test_dir],
                                                        "#{test}:#{scenario}")
                else
                  retry_queue << build_cucumber_command(failed_test[:title], [], failed_test[:options][:env],
                                                        failed_test[:options][:cucumber_rerun_file],
                                                        failed_test[:options][:test_dir],
                                                        "#{test}")
                end
              end
            end
          elsif failed_test[:options][:retry_indivigually] && failed_test[:output].include?("Failure:") && failed_test[:output].include?("rake_test_loader")
            found_test = false
            failed_test[:output].lines.each do |line|
              if line =~ /\A(test_\w+)\((\w+Test)\) \[\/.*\/(test\/.*_test\.rb):(\d+)\]:/
                found_test = true
                test_name = $1
                class_name = $2
                file_name = $3

                # determine if the first part of the command is a directory change
                # if so, include that in the retry command
                chdir_command = ""
                if cmd =~ /\A(cd .+?; )/
                  chdir_command = $1
                end
                retry_queue << build_rake_command("#{class_name} (#{test_name})", "#{chdir_command} ruby -Ilib:test #{file_name} -n #{test_name}", true)
              end
            end
            retry_queue << {
                :command  => failed_test[:command],
                :options  => failed_test[:options],
                :title    => failed_test[:title]
            }
          else
            retry_queue << {
                :command => failed_test[:command],
                :options => failed_test[:options],
                :title   => failed_test[:title]
            }
          end
        end
      end
      retry_queue
    end

    def build_cucumber_command(title="", tags=[], env = {}, old_rerun_file=nil, test_dir="/data/openshift-test/tests",
        feature_file="*.feature", require_gemfile_dir=nil, other_outputs = nil)

      other_outputs ||= {:junit => '/tmp/rhc/cucumber_results'}
      rerun_file = "/tmp/rerun_#{SecureRandom.hex}.txt"
      opts = []
      opts << "--strict"
      opts << "-f progress"
      opts << "-f rerun --out #{rerun_file} "
      other_outputs.each do |formatter, file|
        opts << "-f #{formatter} --out #{file}"
      end
      case(BASE_OS)
        when "rhel" || "centos" then
          tags += ["~@fedora-18-only", "~@fedora-19-only", "~@not-rhel", "~@jboss", "~@not-origin"]
        when "fedora-19"
          tags += ["~@fedora-18-only", "~@rhel-only", "~@not-fedora-19", "~@jboss", "~@not-origin"]
        when "fedora-18"
          tags += ["~@fedora-19-only", "~@rhel-only", "~@not-fedora-18", "~@jboss", "~@not-origin"]
      end
      opts += tags.map{ |t| "-t #{t}"}
      opts << "-r #{test_dir}"
      if old_rerun_file.nil?
        opts << "#{test_dir}/#{feature_file}"
      else
        opts << "@#{old_rerun_file}"
      end
      if not require_gemfile_dir.nil?
        {:command => wrap_test_command("cd #{require_gemfile_dir}; bundle install --path=gems; bundle exec \"cucumber #{opts.join(' ')}\"", env),
         :options =>
             {:cucumber_rerun_file => rerun_file,
              :timeout => @@SSH_TIMEOUT,
              :test_dir => test_dir,
              :env => env,
              :require_gemfile_dir => require_gemfile_dir,
              :other_outputs => other_outputs
             },
         :title => title
        }
      else
        {:command => wrap_test_command("cucumber #{opts.join(' ')}", env),
         :options => {
             :cucumber_rerun_file => rerun_file,
             :timeout => @@SSH_TIMEOUT,
             :test_dir => test_dir,
             :env => env,
             :other_outputs => other_outputs
         },
         :title => title}
      end
    end

    def build_rake_command(title="", cmd="", env = {}, retry_indivigually=true)
      {:command => wrap_test_command(cmd, env), :options => {:retry_indivigually => retry_indivigually, :timeout => @@SSH_TIMEOUT, :env => env}, :title => title}
    end

    def wrap_test_command(command, env={})
      env_str = ""
      unless env.nil?
        env.each do |k,v|
          env_str += "export #{k}=#{v}; "
        end
      end
      if BASE_OS.start_with? "fedora"
        if env["SKIP_RUNCON"]
          "sudo bash -c \"export REGISTER_USER=1 ; #{env_str} #{command}\""
        else
          "sudo bash -c \"runcon -t openshift_initrc_t bash -c \\\"export REGISTER_USER=1 ; #{env_str} #{command}\\\"\""
        end
      elsif(BASE_OS == "rhel" or BASE_OS == "centos")
        "sudo bash -c \"/usr/bin/scl enable ruby193 \\\"export LANG=en_US.UTF-8 ; export REGISTER_USER=1; #{env_str} #{command}\\\"\""
      end
    end
  end
end
