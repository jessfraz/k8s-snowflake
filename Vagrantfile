# -*- mode: ruby -*-
# # vi: set ft=ruby :

require 'fileutils'

Vagrant.require_version ">= 1.9.0"

# Defaults for config options defined in CONFIG
$num_controllers = 1
$num_workers = ENV["WORKERS"].to_i

$vm_gui = false
$vm_memory = 1024
$vm_cpus = 1
$subnet = "172.17.8"

Vagrant.configure("2") do |config|
  # always use Vagrants insecure key
  config.ssh.insert_key = false
  config.vm.box = "bento/ubuntu-16.04"
  config.ssh.username = "vagrant"
  # plugin conflict
  if Vagrant.has_plugin?("vagrant-vbguest") then
    config.vbguest.auto_update = false
  end
  ["vmware_fusion", "vmware_workstation"].each do |vmware|
    config.vm.provider vmware do |v|
      v.vmx['memsize'] = $vm_memory
      v.vmx['numvcpus'] = $vm_cpus
    end
  end
  config.vm.provider :virtualbox do |vb|
    vb.gui = $vm_gui
    vb.memory = $vm_memory
    vb.cpus = $vm_cpus
  end

  # controller node
  config.vm.define vm_name = "controller-node" do |config|
    config.vm.hostname = vm_name
    ip = "#{$subnet}.100"
    config.vm.network :private_network, ip: ip
    config.vm.provision "shell", path: "vagrant/_configure.sh"
  end

  # workers
  (0..$num_workers).each do |i|
    config.vm.define vm_name = "worker-node-#{i}" do |config|
      config.vm.hostname = vm_name
      ip = "#{$subnet}.#{i+101}"
      config.vm.network :private_network, ip: ip
      config.vm.provision "shell", path: "vagrant/_configure.sh"
    end
  end

end
