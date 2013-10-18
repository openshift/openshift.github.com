#
# Global definitions
#

OPTIONS = {
  "fedora-19" => {
    "amis"            => {"us-east-1" =>"ami-b22e5cdb"},
    "devenv_name"     => "oso-fedora",
    "ignore_packages" => [
      'openshift-origin-util-scl',
      'rubygem-openshift-origin-auth-kerberos',

      #carts
      #'openshift-origin-cartridge-ruby',
      #'openshift-origin-cartridge-perl',
      #'openshift-origin-cartridge-python',
      'openshift-origin-cartridge-jbosseap',
      #'openshift-origin-cartridge-jbossas',
      'openshift-origin-cartridge-jbossews',
      #'openshift-origin-cartridge-mysql',
      #'openshift-origin-cartridge-cron',
      #'openshift-origin-cartridge-ceylon',
      #'openshift-origin-cartridge-tomcat',
      'openshift-origin-cartridge-switchyard',
      'rubygem-openshift-origin-container-libvirt',
      #'rubygem-openshift-origin-admin-console',
    ],
    "cucumber_options"        => '--strict -f progress -f html -t ~@rhel-only -t ~@jboss -t ~@not-origin',
    "broker_cucumber_options" => '--strict -f progress -f html --out /tmp/rhc/broker_cucumber.html -f progress  -t ~@rhel-only -t ~@jboss',
  },
  "rhel"   => {
    "amis"            => {"us-east-1" =>"ami-7d0c6314"},
    "devenv_name"     => "oso-rhel",
    "ignore_packages" => [
      'rubygem-openshift-origin-auth-kerberos',
      'openshift-origin-util',
      'avahi-cname-manager',
      'rubygem-openshift-origin-dns-avahi',
      'openshift-origin-cartridge-infinispan-5.2',
      'openshift-origin-cartridge-jbossas',
      'openshift-origin-cartridge-mariadb',
      'openshift-origin-cartridge-jbossews',
      'openshift-origin-cartridge-jbosseap',
      'openshift-origin-cartridge-ceylon',
      'openshift-origin-cartridge-tomcat',
      'openshift-origin-cartridge-ceylon-0.5',
      #'rubygem-openshift-origin-admin-console',
      'rubygem-openshift-origin-container-libvirt',
    ],
    "cucumber_options"        => '--strict -f progress -f junit --out /tmp/rhc/cucumber_results -t ~@fedora-only -t ~@jboss -t ~@not-origin',
    "broker_cucumber_options" => '--strict -f html --out /tmp/rhc/broker_cucumber.html -f progress  -t ~@fedora-only -t ~@jboss',    
  },
}

TYPE = "m1.large"
ZONE = 'us-east-1d'
VERIFIER_REGEXS = {}
TERMINATE_REGEX = /terminate/
VERIFIED_TAG = "qe-ready"

# Specify the source location of the SSH key
# This will be used if the key is not found at the location specified by "RSA"
KEY_PAIR = "libra"
RSA = File.expand_path("~/.ssh/devenv.pem")
RSA_SOURCE = ""

SAUCE_USER = ""
SAUCE_SECRET = ""
SAUCE_OS = ""
SAUCE_BROWSER = ""
SAUCE_BROWSER_VERSION = ""
CAN_SSH_TIMEOUT=90
SLEEP_AFTER_LAUNCH=60

SIBLING_REPOS = {
  'origin-server' => ['../origin-server'],
  'rhc' => ['../rhc'],
  'origin-dev-tools' => ['../origin-dev-tools'],
  'openshift-pep' => ['../openshift-pep'],
  'puppet-openshift_origin' => ['../puppet-openshift_origin'],
}
OPENSHIFT_ARCHIVE_DIR_MAP = {'rhc' => 'rhc/'}
SIBLING_REPOS_GIT_URL = {
  'origin-server' => 'https://github.com/openshift/origin-server.git',
  'rhc' => 'https://github.com/openshift/rhc.git',
  'origin-dev-tools' => 'https://github.com/openshift/origin-dev-tools.git',
  'openshift-pep' => 'https://github.com/openshift/openshift-pep.git',
  'puppet-openshift_origin' => 'https://github.com/openshift/puppet-openshift_origin.git'
}

DEV_TOOLS_REPO = 'origin-dev-tools'
DEV_TOOLS_EXT_REPO = DEV_TOOLS_REPO
ADDTL_SIBLING_REPOS = SIBLING_REPOS_GIT_URL.keys - [DEV_TOOLS_REPO]
ACCEPT_DEVENV_SCRIPT = 'true'
$amz_options = {:key_name => KEY_PAIR, :instance_type => TYPE}

def guess_os(base_os=nil)
  return base_os unless base_os.nil?
  if File.exist?("/etc/fedora-release")
    version = File.open("/etc/fedora-release").read.match(/[\w ]*release ([\d]+) [.]*/)[1]
    return "fedora-#{version}"
  elsif File.exist?("/etc/redhat-release")
    data = File.read("/etc/redhat-release")
    if data.match(/centos/)
      return "centos"
    else
      return "rhel"
    end
  end
end

def def_constants(base_os="fedora-19")
  Object.const_set(:AMI, OPTIONS[base_os]["amis"]) unless Object.const_defined?(:AMI)
  Object.const_set(:DEVENV_NAME, OPTIONS[base_os]["devenv_name"]) unless Object.const_defined?(:DEVENV_NAME)
  Object.const_set(:IGNORE_PACKAGES, OPTIONS[base_os]["ignore_packages"]) unless Object.const_defined?(:IGNORE_PACKAGES)
  Object.const_set(:CUCUMBER_OPTIONS, OPTIONS[base_os]["cucumber_options"]) unless Object.const_defined?(:CUCUMBER_OPTIONS)
  Object.const_set(:BROKER_CUCUMBER_OPTIONS, OPTIONS[base_os]["broker_cucumber_options"]) unless Object.const_defined?(:BROKER_CUCUMBER_OPTIONS)
  Object.const_set(:BASE_OS, base_os) unless Object.const_defined?(:BASE_OS)

  scl_root = ""
  scl_prefix = ""
  if(BASE_OS == "rhel" or BASE_OS == "centos")
    scl_root = "/opt/rh/ruby193/root"
    scl_prefiex = "ruby193-"
  end
  Object.const_set(:SCL_ROOT, scl_root) unless Object.const_defined?(:SCL_ROOT)
  Object.const_set(:SCL_PREFIX, scl_prefix) unless Object.const_defined?(:SCL_PREFIX)
end
