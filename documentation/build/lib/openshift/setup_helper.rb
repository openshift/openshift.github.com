module SetupHelper
  BUILD_REQUIREMENTS = ["tito","yum-plugin-priorities","git","make","wget","vim-enhanced","rubygems","ruby-devel","rubygems-devel"]
  BUILD_GEM_REQUIREMENTS = {"aws-sdk"=>"","rake"=>"","thor"=>"","parseconfig"=>"","yard"=>"","redcarpet"=>""}

  def self.is_gem_installed?(base_os, gem_name, version='')
    if version.nil? or version.empty?
      if(base_os == "rhel" or base_os == "centos")
        `scl enable ruby193 "gem list -i #{gem_name}"`
      else
        `gem list -i #{gem_name}`
      end
      is_installed = ($? == 0)
    else
      if(base_os == "rhel" or base_os == "centos")
        `scl enable ruby193 "gem list -i #{gem_name} -v #{version}"`
      else
        `gem list -i #{gem_name} -v #{version}`
      end
      is_installed = ($? == 0)
    end
    return is_installed
  end
  
  def self.install_gem(base_os, gem_name, version='',try_rpm=false)
    install_succeeded = false
    puts "Installing gem #{gem_name}"
    if try_rpm
      scl_prefix = File.exist?("/etc/fedora-release") ? "" : "ruby193-"
      install_succeeded = system "yum install -y '#{scl_prefix}rubygem-#{gem_name}'"
    end
    unless install_succeeded
      if version.nil? or version.empty?
        print `gem install #{gem_name}`
      else
        print `gem install #{gem_name} -v #{version}`
      end
    end
  end
  
  # Ensure that openshift mirror repository and all build requirements are installed.
  # On RHEL6, it also verifies that the build script is running within SCL-Ruby 1.9.3.
  def self.ensure_build_requirements
    if File.exist?("/etc/redhat-release")
      packages = BUILD_REQUIREMENTS.select{ |rpm| `rpm -q #{rpm}`.match(/is not installed/) }
      if packages.length > 0
        puts "You are the following packages which are required to run this build script. Installing..."
        puts packages.map{|p| "\t#{p}"}.join("\n")
        system "yum install -y #{packages.join(" ")}"
      end
      
      create_openshift_deps_rpm_repository
      if `rpm -q puppet`.match(/is not installed/)
        system "yum install -y --enablerepo puppetlabs-products facter puppet"
      end
      
      base_os = guess_os
      if(base_os == "rhel" or base_os == "centos")
        system "yum install -y scl-utils ruby193 ruby193-rubygem-cucumber"
      end
    end
    
    missing_gems = {}
    BUILD_GEM_REQUIREMENTS.each do |gem_name, version|
      missing_gems[gem_name]=version unless is_gem_installed?(base_os, gem_name, version)
    end
    
    if missing_gems.keys.length > 0
      print "Installing required gems\n"
      missing_gems.each do |gem_name, version|
        install_gem(base_os, gem_name, version, File.exist?("/etc/redhat-release"))
      end
    end
    
    if RUBY_VERSION.to_f < 1.9
      if(guess_os == "rhel" or guess_os == "centos")
        puts "Unsupported ruby version #{RUBY_VERSION}. Please ensure that you are running within a ruby193 scl container\n"
        exit
      else
        #puts "Unsupported ruby version #{RUBY_VERSION}. Please ensure that you are running Ruby 1.9.3\n"
        #exit
      end
    end
  end

  # Create a RPM repository for OpenShift Origin dependencies available on the mirror.openshift.com site
  def self.create_openshift_deps_rpm_repository
    if(guess_os == "rhel" or guess_os == "centos")
      url = "https://mirror.openshift.com/pub/origin-server/nightly/rhel-6/dependencies/x86_64/"
    elsif guess_os == "fedora-19"
      url = "https://mirror.openshift.com/pub/origin-server/nightly/fedora-19/dependencies/x86_64/"
    end

    unless File.exist?("/etc/yum.repos.d/openshift-origin-deps.repo")
      File.open("/etc/yum.repos.d/openshift-origin-deps.repo","w") do |file|
        file.write %{
[openshift-origin-deps]
name=openshift-origin-deps
baseurl=#{url}
gpgcheck=0
enabled=1
        }
      end
    end
  end
end
