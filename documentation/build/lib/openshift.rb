#!/usr/bin/env ruby

$: << File.expand_path(File.dirname(__FILE__))

require 'logger'
require 'net/smtp'
require 'openshift/ssh'
require 'openshift/tito'
require 'openshift/amz'
require 'openshift/builder_helper'

# Force synchronous stdout
STDOUT.sync, STDERR.sync = true

# Setup logger
$log = Logger.new(STDOUT)
$log.level = Logger::DEBUG

def log
  $log
end

def exit_msg(msg)
  puts msg
  exit 0
end

def get_branch
  branch_str = `git status | head -n1`.chomp
  branch_str =~ /.*branch (.*)/
  branch = $1 ? $1 : 'origin/master'
  return branch
end

def send_verified_email(image_id, image_name)
  msg = <<END_OF_MESSAGE   
From: Jenkins <noreply@redhat.com>
To: Libra Team <libra-devel@redhat.com>
Subject: [Jenkins] DevEnv Image #{image_name} (#{image_id}) is QE Ready

Image #{image_name} (#{image_id}) has passed validation tests and is ready for QE.

END_OF_MESSAGE

  Net::SMTP.start('localhost') do |smtp|
    smtp.send_message msg, "noreply@redhat.com", "libra-devel@redhat.com"
  end
end
