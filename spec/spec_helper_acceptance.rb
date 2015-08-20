require 'beaker-rspec/spec_helper'
require 'beaker-rspec/helpers/serverspec'

def project_root
  File.expand_path(File.join(File.dirname(__FILE__), '..'))
end

def find_hosts_with_role(role)
  hosts.select { |h| h[:roles].include?(role) }
end

#def install_pe_on(role)
#  target_hosts = find_hosts_with_role role
#
#  target_hosts.each do |host|
#    #process the version files if necessary
#    host['pe_dir'] ||= options[:pe_dir]
#    host['pe_ver'] = host['pe_ver'] || options['pe_ver'] ||
#     Beaker::Options::PEVersionScraper.load_pe_version(host[:pe_dir] || options[:pe_dir], options[:pe_version_file])
#
#    pe_installed = (on host, '[ -d /etc/puppetlabs ]').exit_code == 0
#    unless pe_installed
#      #send in the global options hash
#      do_install host, options
#    end
#  end
#end

def install_satellite_on(role)
  target_hosts = find_hosts_with_role role
  target_hosts.each do |host|
    fqdn = on(host, "hostname --fqdn").stdout.strip
    on host, "grep #{fqdn} /etc/hosts || sed -i 's/satellite/#{fqdn} satellite/' /etc/hosts"
    on host, "service firewalld stop"
    run_script_on host, project_root + '/config/scripts/install_satellite.sh'
  end
end

unless ENV['RS_PROVISION'] == 'no' or ENV['BEAKER_provision'] == 'no'
  install_pe
  install_satellite_on 'satellite'
  on "master", puppet('module install puppetlabs-inifile'), { :acceptable_exit_codes => [0,1] }
end

RSpec.configure do |c|
  # Readable test descriptions
  c.formatter = :documentation

  # Configure all nodes in nodeset
  c.before :suite do
    # Install module and dependencies
    copy_module_to('master', :source => project_root, :module_name => 'pe_satellite')
  end
end

require 'json'
require 'rest-client'

def satellite_post(ip, resource, json_data)
  url = "https://#{ip}/api/v2/"
  full_url = url + resource

  begin
    response = RestClient::Request.new(
      :method => :put,
      :url => full_url,
      :user => "admin",
      :password => "puppetlabs",
      :headers => { :accept => :json,
      :content_type => :json},
      :payload => json_data,
      :verify_ssl => false
    ).execute
    results = JSON.parse(response.to_str)
  rescue => e
    e.response
  end
end

def satellite_get(ip, resource)
  url = "https://#{ip}/api/v2/"
  full_url = url + resource

  begin
    response = RestClient::Request.new(
      :method => :get,
      :url => full_url,
      :user => "admin",
      :password => "puppetlabs",
      :verify_ssl => false,
      :headers => { :accept => :json,
    :content_type => :json }
    ).execute
    results = JSON.parse(response.to_str)
  rescue => e
    e.response
  end
end

def satellite_update_setting(ip, setting, value)
  satellite_post(ip, "settings/#{setting}", JSON.generate(
    {
      "id"=> "#{setting}", 
      "setting" => {"value" => value}
    })
  )
end

def satellite_get_last_report(ip)
  satellite_get(ip, "hosts/master/reports/last")['logs'].join("\n")
end
