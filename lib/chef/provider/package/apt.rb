#
# Author:: Adam Jacob (<adam@opscode.com>)
# Copyright:: Copyright (c) 2008 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'timeout'

require 'chef/provider/package'
require 'chef/mixin/command'
require 'chef/resource/package'
require 'chef/mixin/shell_out'
require 'chef/mixin/file'


class Chef
  class Provider
    class Package
      class Apt < Chef::Provider::Package

        include Chef::Mixin::ShellOut
        attr_accessor :is_virtual_package

        def load_current_resource
          @current_resource = Chef::Resource::Package.new(@new_resource.name)
          @current_resource.package_name(@new_resource.package_name)
          check_package_state(@new_resource.package_name)
          @current_resource
        end

        def default_release_options
          # Use apt::Default-Release option only if provider was explicitly defined
          "-o APT::Default-Release=#{@new_resource.default_release}" if @new_resource.provider && @new_resource.default_release
        end

        def check_package_state(package)
          Chef::Log.debug("#{@new_resource} checking package status for #{package}")
          installed = false

          shell_out!("apt-cache#{expand_options(default_release_options)} policy #{package}").stdout.each_line do |line|
            case line
            when /^\s{2}Installed: (.+)$/
              installed_version = $1
              if installed_version == '(none)'
                Chef::Log.debug("#{@new_resource} current version is nil")
                @current_resource.version(nil)
              else
                Chef::Log.debug("#{@new_resource} current version is #{installed_version}")
                @current_resource.version(installed_version)
                installed = true
              end
            when /^\s{2}Candidate: (.+)$/
              candidate_version = $1
              if candidate_version == '(none)'
                # This may not be an appropriate assumption, but it shouldn't break anything that already worked -- btm
                @is_virtual_package = true
                showpkg = shell_out!("apt-cache showpkg #{package}").stdout
                providers = Hash.new
                showpkg.rpartition(/Reverse Provides:? #{$/}/)[2].each_line do |line|
                  provider, version = line.split
                  providers[provider] = version
                end
                # Check if the package providing this virtual package is installed
                num_providers = providers.length
                raise Chef::Exceptions::Package, "#{@new_resource.package_name} has no candidate in the apt-cache" if num_providers == 0
                # apt will only install a virtual package if there is a single providing package
                raise Chef::Exceptions::Package, "#{@new_resource.package_name} is a virtual package provided by #{num_providers} packages, you must explicitly select one to install" if num_providers > 1
                # Check if the package providing this virtual package is installed
                Chef::Log.info("#{@new_resource} is a virtual package, actually acting on package[#{providers.keys.first}]")
                installed = check_package_state(providers.keys.first)
              else
                Chef::Log.debug("#{@new_resource} candidate version is #{$1}")
                @candidate_version = $1
              end
            end
          end

          return installed
        end

        def install_package(name, version)
          package_name = "#{name}=#{version}"
          package_name = name if @is_virtual_package
          AptDB::Locks.wait_on_lock(300)
          run_command_with_systems_locale(
            :command => "apt-get -q -y#{expand_options(default_release_options)}#{expand_options(@new_resource.options)} install #{package_name}",
            :environment => {
              "DEBIAN_FRONTEND" => "noninteractive"
            }
          )
        end

        def upgrade_package(name, version)
          install_package(name, version)
        end

        def remove_package(name, version)
          package_name = "#{name}"
          run_command_with_systems_locale(
            :command => "apt-get -q -y#{expand_options(@new_resource.options)} remove #{package_name}",
            :environment => {
              "DEBIAN_FRONTEND" => "noninteractive"
            }
          )
        end

        def purge_package(name, version)
          run_command_with_systems_locale(
            :command => "apt-get -q -y#{expand_options(@new_resource.options)} purge #{@new_resource.package_name}",
            :environment => {
              "DEBIAN_FRONTEND" => "noninteractive"
            }
          )
        end

        def preseed_package(preseed_file)
          Chef::Log.info("#{@new_resource} pre-seeding package installation instructions")
          run_command_with_systems_locale(
            :command => "debconf-set-selections #{preseed_file}",
            :environment => {
              "DEBIAN_FRONTEND" => "noninteractive"
            }
          )
        end

        def reconfig_package(name, version)
          Chef::Log.info("#{@new_resource} reconfiguring")
          run_command_with_systems_locale(
            :command => "dpkg-reconfigure #{name}",
            :environment => {
              "DEBIAN_FRONTEND" => "noninteractive"
            }
          )
        end

      end
    end
  end
end

module AptDB
  module Locks
    #This function opens the file passed, and checks to see if it is locked
    def self.is_locked? fname
      f = File.new(fname)
      if f.flocked?
        f.close
        return true
      else
        f.close
        return false
      end
    end

    #This function runs through possible apt lock files and checks for a current lock
    def self.apt_locked?
      lock_files = [
        "/var/lib/dpkg/lock",
        "/var/lock/aptitude",
        "/var/cache/apt/archives/lock",
        "/var/lib/apt/lists/lock"
      ]

      lock_files.each do |f|
        if File.exists?(f) and is_locked?(f)
          return true
        end
      end
      return false
    end

    #This function will ask if apt is locked and sleep
    def self.wait_on_lock( timeout_sec = 60 )
      begin
        Timeout::timeout(timeout_sec) do
          if apt_locked?
            Chef::Log.warn("Apt DB is locked. Sleeping...")
            while apt_locked?
              sleep(5)
            end
            Chef::Log.info("Apt DB is free. Waking up.")
          end
        end
      rescue
        Chef::Application.fatal!("Apt has been locked for too long.", -10)
      end
    end
  end
end
