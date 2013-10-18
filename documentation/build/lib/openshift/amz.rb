require 'parseconfig'
require 'pp'
require 'aws'
require 'aws-sdk'
require 'date'

module OpenShift
  module Amazon
    FEDORA_SYSTEM_CA_FILE = "/etc/pki/tls/certs/ca-bundle.trust.crt"

    def setup_rsa_key
      unless File.exists?(RSA)
        log.info "Setting up RSA key..."
        ssh_key = RSA_SOURCE
        log.info "Key location = " + ssh_key
        log.info "Destination = " + RSA
        FileUtils.mkdir_p File.dirname(RSA)
        FileUtils.chmod 0700, File.dirname(RSA)
        FileUtils.cp ssh_key, RSA
        FileUtils.chmod 0600, RSA
      end
    end

    def connect(region=nil)
      conn = nil
      begin
        # Setup the SSH key
        setup_rsa_key

        setup_aws_config "~/.awscred"

        # Return the AMZ connection
        conn = AWS::EC2.new
      end

      conn = conn.regions[region] if region
      conn
    end

    def check_update
      yum_output = `yum check-update rhc-*`

      packages = {}
      yum_output.split("\n").each do |line|
        if line.start_with?("Obsoleting")
          break
        elsif line.start_with?("rhc")
          pkg_name = line.split[0]
          version = line.split[1]
          packages[pkg_name] = version
        end
      end

      packages
    end

    def get_amis(conn, filter)
      conn.images.with_owner(:self).
        filter("state", "available").
        filter("name", filter)
    end
          
    def delete_detached_volumes(conn)
      volumes = conn.volumes.filter("status", "available")
      volumes.each do |volume|
        if volume.create_time.to_i < (Time.now.to_i - 10800)
          puts "Deleting #{volume.size}GB detached volume: #{volume.id}"
          volume.delete
        end
      end
    end
          
    def delete_unused_snapshots(conn)
      snapshots = conn.snapshots.with_owner(:self).filter("status", "completed")
      snapshots.each do |snapshot|
        if snapshot.start_time.to_i < (Time.now.to_i - 10800)
          begin
            snapshot.delete
          rescue AWS::EC2::Errors::InvalidSnapshot::InUse => e
          else
            puts "Deleted #{snapshot.volume_size}GB unused snapshot: #{snapshot.id}"
          end
        end
      end
    end
    
    def get_specific_public_ami(conn, filter_val)
      if filter_val.start_with?("ami")
        filter_param = "image-id"
      else
        filter_param = "name"
      end 
      AWS.memoize do
        devenv_amis = conn.images.
          filter("state", "available").
          filter(filter_param, filter_val)
        # Take the last DevEnv AMI - memoize saves a remote call
        devenv_amis.to_a[0]
      end
    end
    
    def get_specific_ami(conn, filter_val)
      if filter_val.start_with?("ami")
        filter_param = "image-id"
      else
        filter_param = "name"
      end 
      AWS.memoize do
        devenv_amis = conn.images.with_owner(:self).
          filter("state", "available").
          filter(filter_param, filter_val)
        # Take the last DevEnv AMI - memoize saves a remote call
        devenv_amis.to_a[0]

      end
    end

    def get_latest_ami(conn, filter_val)
      AWS.memoize do
        # Limit to DevEnv images
        devenv_amis = conn.images.with_owner(:self).
          filter("state", "available").
          filter("name", filter_val)
        # Take the last DevEnv AMI - memoize saves a remote call
        devenv_amis.to_a.sort_by {|ami| ami.name.split("_")[-1].to_i}.last
      end
    end

    def instance_status(instance)
      (1..10).each do |index|
        begin
          status = instance.status
          return status
        rescue Exception => e
          if index == 10
            instance.terminate
            raise
          end
          log.info "Error getting status(retrying): #{e.message}"
          sleep 30
        end
      end
    end

    def find_instance(conn, name, use_tag=false, block_until_available=true, ssh_user="root", silent=false)
      if use_tag
        instances = conn.instances.filter('tag-key', 'Name').filter('tag-value', name)
      else
        instances = conn.instances.filter('dns-name', name)
      end
      instances.each do |i|
        if (instance_status(i) != :terminated)
          puts "Found instance #{i.id} (#{i.tags["Name"]})" unless silent
          block_until_available(i, ssh_user) if block_until_available
          return i
        end
      end

      puts "No instance found matching #{name}"

      # If we are searching by tag, then find instances with names for
      # which the given name is a prefix, and suggest these instances.
      matches = 0
      if use_tag
        instances = conn.instances.filter('tag-key', 'Name').filter('tag-value', "#{name}*")
        instances.each do |i|
          if (instance_status(i) != :terminated)
            puts "Did you mean one of the following?" if matches == 0
            puts "  #{i.tags["Name"]}"
            matches = matches + 1
          end
        end
      end

      return nil
    end
      
    def terminate_instance(instance, handle_unauthorized=false)
      if !instance.api_termination_disabled?
        begin
          (0..4).each do
            instance.terminate
            (0..12).each do
              break if instance_status(instance) == :terminated
              log.info "Instance isn't terminated yet... waiting"
              sleep 5
            end
            break if instance_status(instance) == :terminated
            log.info "Instance isn't terminated yet... retrying"
          end
        rescue AWS::EC2::Errors::UnauthorizedOperation
          raise unless handle_unauthorized
          log.info "You do not have permission to terminate instances."
        ensure
          if instance_status(instance) != :terminated
            log.info "Failed to terminate.  Calling stop instead."
            tag_to_terminate(instance)
            begin
              instance.stop
            rescue Exception => e
              log.info "Failed to stop: #{e.message}"
            end
          end
        end
      else
        puts "Termination protection is enabled for: #{instance.id} (#{instance.tags["Name"]})"
      end
    end
        
    def add_tag(instance, name, retries=2)
      (1..retries).each do |i|
        begin
          # Tag the instance
          instance.add_tag('Name', :value => name)
        rescue Exception => e
          log.info "Failed adding tag: #{e.message}"
          raise if i == retries
          sleep 5
        end
      end
    end

    def launch_instance(image, name, max_retries = 1, ssh_user="root")
      log.info "Creating new instance..."

      # You may have to retry creating instances since Amazon
      # fails at bringing them up every once in a while
      retries = 0

      # Launch a new instance
      instance = image.run_instance($amz_options)

      begin
        add_tag(instance, name, 20)

        # Block until the instance is accessible
        block_until_available(instance, ssh_user, true)

        return instance
      rescue ScriptError => e
        # Handles retrying instance creation for instances that
        # didn't come up with SSH access in time
        if retries <= max_retries
          log.info "Retrying instance creation (attempt #{retries + 1})..."

          # Terminate the current instance since it didn't load
          terminate_instance(instance, true)

          # Launch a new instance
          instance = image.run_instance($amz_options)

          # Retry the above logic to verify accessibility
          retries += 1
          retry
        else
          puts e.message
          exit 1
        end
      end
    end

    def block_until_available(instance, ssh_user="root", terminate_if_unavailable=false)
      log.info "Waiting for instance to be available..."

      (0..24).each do
        break if instance_status(instance) == :running
        log.info "Instance isn't running yet... retrying"
        sleep 5
      end

      unless instance_status(instance) == :running
        terminate_instance(instance) if terminate_if_unavailable
        raise ScriptError, "Instance is not in a state of 'running'"
      end

      hostname = instance.dns_name
      (1..30).each do
        break if can_ssh?(hostname, ssh_user)
        log.info "SSH access failed... retrying"
        sleep 5
      end

      unless can_ssh?(hostname, ssh_user)
        terminate_instance(instance, true)
        raise ScriptError, "SSH availability timed out"
      end

      log.info "Instance (#{hostname}) is accessible"
    end

    def is_valid?(hostname, ssh_user="root")
      @validation_output = ssh(hostname, ACCEPT_DEVENV_SCRIPT, 60, false, 1, ssh_user)
      if @validation_output == "PASS"
        return true
      else
        puts "Node Acceptance Output = #{@validation_output}"
        return false
      end
    end

    def get_private_ip(hostname, ssh_user="root")
      private_ip = ssh(hostname, "facter ipaddress", 60, false, 1, ssh_user)
      if !private_ip or private_ip.strip.empty?
        puts "EXITING - AMZ instance didn't return ipaddress fact"
        exit 0
      end
      private_ip
    end
    
    def use_private_ip(hostname, ssh_user="root")
      private_ip = get_private_ip(hostname)
      puts "Updating instance facts with private ip #{private_ip}"
      set_instance_ip(hostname, private_ip, private_ip, ssh_user)
    end

    def use_public_ip(hostname, ssh_user="root")
      dhostname = ssh(hostname, "wget -qO- http://169.254.169.254/latest/meta-data/public-hostname", 60, false, 1, ssh_user)
      public_ip = ssh(hostname, "wget -qO- http://169.254.169.254/latest/meta-data/public-ipv4", 60, false, 1, ssh_user)
      puts "Updating instance facts with public ip #{public_ip} and hostname #{dhostname}"
      set_instance_ip(hostname, public_ip, dhostname, ssh_user)
    end

    def get_internal_hostname(hostname, ssh_user="root")
      internal_hostname = ssh(hostname, "hostname", 60, false, 1, ssh_user)
      internal_hostname
    end

    def update_facts(hostname, ssh_user="root")
      puts "Updating instance facts and running libra-data to set the public ip..."
      ssh(hostname, "sed -i \"s/.*PUBLIC_IP_OVERRIDE.*/#PUBLIC_IP_OVERRIDE=/g\" /etc/openshift/node.conf; sed -i \"s/.*PUBLIC_HOSTNAME_OVERRIDE.*/#PUBLIC_HOSTNAME_OVERRIDE=/g\" /etc/openshift/node.conf; #{SCL_ROOT}/usr/libexec/mcollective/update_yaml.rb /etc/mcollective/facts.yaml; service libra-data start", 60, false, 1, ssh_user)
      puts 'Done'
    end
    
    def set_instance_ip(hostname, ip, dhostname, ssh_user="root")
      print "Updating the controller to use the ip '#{ip}'..."
      # Both calls below are needed to fix a race condition between ssh and libra-data start times
      ssh(hostname, "sed -i \"s/.*PUBLIC_IP_OVERRIDE.*/PUBLIC_IP_OVERRIDE='#{ip}'/g\" /etc/openshift/node.conf; sed -i \"s/.*PUBLIC_HOSTNAME_OVERRIDE.*/PUBLIC_HOSTNAME_OVERRIDE='#{dhostname}'/g\" /etc/openshift/node.conf; #{SCL_ROOT}/usr/libexec/mcollective/update_yaml.rb /etc/mcollective/facts.yaml", 60, false, 1, ssh_user)
      puts 'Done'
    end

    def verify_image(image)
      log.info "Tagging image (#{image.id}) as '#{VERIFIED_TAG}'..."
      image.add_tag('Name', :value => VERIFIED_TAG)
      log.info "Done"
    end
    
    def register_image(conn, instance, name, manifest)
      puts "Registering AMI..."
      outer_num_retries = 4
      image = nil
      (1..outer_num_retries).each do |outer_index|
        image = conn.images.create(:instance_id => instance.id, 
          :name => name,
          :description => manifest)
        num_retries = 10
        (1..num_retries).each do |index|
          begin
            sleep 30 until image.state == :available
            puts "Sleeping for 30 seconds to let image stabilize..."
            sleep 30
            break
          rescue Exception => e
            raise if index == num_retries && outer_index == outer_num_retries
            if index == num_retries
              log.info "Error getting state: #{e.message}"
              log.info "Deregistering image: #{image.name}"
              image.deregister
              image = nil
            else
              log.info "Error getting state(retrying): #{e.message}"
            end
            sleep 30
          end
        end
        break if image
      end
      puts "Image ID: #{image.id}"
      puts "Image Name: #{image.name}"
      puts "Done"
      image
    end

    def terminate_flagged_instances(conn)
      AWS.memoize do
        conn.instances.each do |i|
          if ((instance_status(i) == :stopped) || (instance_status(i) == :running)) && (i.tags["Name"] =~ TERMINATE_REGEX)
            log.info "Terminating #{i.id} (#{i.tags["Name"]})"
            terminate_instance(i)
          end
        end
      end
    end
    
    def terminate_old_verifiers(conn)
      AWS.memoize do
        build_name_to_verifiers = {}
        conn.instances.each do |i|
          VERIFIER_REGEXS.each do |regex, opts|
            if i.tags["Name"] =~ regex
              build_name = $1
              build_num = $2
              build_name_to_verifiers[build_name] = [] unless build_name_to_verifiers[build_name]
              build_name_to_verifiers[build_name] << [build_num, i, opts]
            end
          end
        end
        build_name_to_verifiers.each do |build_name, verifiers|
          unless verifiers.empty?
            verifiers = verifiers.sort_by {|verifier| verifier[0].to_i}
            verifiers.each_with_index do |verifier, index|
              build_num = verifier[0]
              i = verifier[1]
              opts = verifier[2]
              max_run_time = opts[:max_run_time] ? opts[:max_run_time] : 9000 #2.5 hours
              if (index == verifiers.length - 1) || opts[:multiple]
                unless Time.new - i.launch_time > max_run_time
                  next
                end
              end
              if instance_status(i) == :running || instance_status(i) == :stopped
                log.info "Terminating verifier #{i.id} (#{i.tags["Name"]})"
                terminate_instance(i)
              end
            end
          end
        end
      end
    end

    def flag_old_devenvs(conn)
      AWS.memoize do
        conn.instances.each do |i|
          if (instance_status(i) == :stopped) && !(i.tags["Name"] =~ /preserve/)
            launch_yday = i.launch_time.yday
            yday = Time.new.yday
            if yday < launch_yday
              yday += 365 # minor leap year bug here (will terminate 1 day late)
            end
            if yday - launch_yday > 6
              tag_to_terminate(i)
            end
          end
        end
      end
    end

    def flag_old_qe_devenvs(conn)
      AWS.memoize do
        conn.instances.each do |i|
          current_time = Time.new
          if i.tags["Name"] =~ /^S?QE(_|-)/i && !(i.tags["Name"] =~ /preserve/)
            if ((current_time - i.launch_time) > 57600) && (instance_status(i) == :running)
              log.info "Stopping qe instance #{i.id} (#{i.tags["Name"]})"
              i.stop
            elsif ((current_time - i.launch_time) > 10800) && (instance_status(i) == :stopped)
              tag_to_terminate(i)
            end
          end
        end
      end
    end

    def stop_untagged_instances(conn)
      AWS.memoize do
        conn.instances.each do |i|
          if (instance_status(i) == :running || instance_status(i) == :stopped) && (i.tags['Name'] == nil)
            tag_to_terminate(i)

            # Stop the nodes to save resources
            log.info "Stopping untagged instance #{i.id} (#{i.tags["Name"]})"
            i.stop
          end
        end
      end
    end
    
    def tag_to_terminate(i)
      if !i.tags["Name"] || !i.tags["Name"].end_with?('-terminate')
        log.info "Tagging instance to terminate #{i.id} (#{i.tags["Name"]})"
        add_tag(i, "#{i.tags["Name"]}-will-terminate")
      end
    end

    private

    def setup_aws_config(path)
        # Parse the credentials
        full_path = File.expand_path(path)
        config = ParseConfig.new(full_path)

        unless config['AWSAccessKeyId'] && config['AWSSecretKey']
          raise <<-EOF
Couldn't access credentials in #{full_path}

Please create a file with the following format:
            AWSAccessKeyId=<ACCESS_KEY>
            AWSSecretKey=<SECRET_KEY>
            # CAFile="path/to/ca_file" # optional
          EOF
        end

        # Setup the global access configuration
        aws_config = {
          :access_key_id => config['AWSAccessKeyId'],
          :secret_access_key => config['AWSSecretKey']
        }

        if config['CAFile']
          aws_config[:ssl_ca_file] = config['CAFile']
        elsif File.exists? FEDORA_SYSTEM_CA_FILE
          aws_config[:ssl_ca_file] = FEDORA_SYSTEM_CA_FILE
        end

        AWS.config( aws_config )
    end

  end
end
