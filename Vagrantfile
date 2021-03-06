# -*- mode: ruby -*-
 # vi: set ft=ruby :

CONTROLLER_NODES = Integer(ENV['CONTROLLER_NODES'] || 2)
WORKER_NODES = Integer(ENV['WORKER_NODES'] || 2)
## resources
# total: MASTER_NODES + WORKER_NODES + LOAD_BALANCER + CLIENT
# do math for resources
CPUS_PER_CONTROLLER = Integer(ENV["CPUS_PER_CONTROLLER"] || 1)
CPUS_PER_WORKER = Integer(ENV["CPUS_PER_WORKER"] || 1)
MEMORY_PER_CONTROLLER = Integer(ENV["MEMORY_PER_CONTROLLER"] || 1024)
MEMORY_PER_WORKER = Integer(ENV["MEMORY_PER_WORKER"] || 1024)
CLIENT_CPUS = Integer(ENV["CLIENT_CPUS"] || 1)
CLIENT_MEMORY = Integer(ENV["CLIENT_MEMORY"] || 512)
LB_CPUS = Integer(ENV["LB_CPUS"] || 1)
LB_MEMORY = Integer(ENV["LB_MEMORY"] || 512)

# change ports to > 1024 on virtualbox (and use iptables) ?
# with libvirt, 80 && 443 are working (we are asked for sudo password on "vagrant up")
HOST_PORTS_STR=ENV['HOST_PORTS'] || '80,443'
GUEST_PORTS_STR=ENV['GUEST_PORTS'] || '80,443'
HOST_PORTS = HOST_PORTS_STR.split(',')
GUEST_PORTS = GUEST_PORTS_STR.split(',')
if HOST_PORTS.length.eql?(GUEST_PORTS.length)
  LB_PORTS = HOST_PORTS.map.with_index { |port, i| { "host" => Integer(port), "guest" => Integer(GUEST_PORTS[i]) } }
else
  # default to 80,443
  LB_PORTS = [
    { "guest" => 80, "host" => 80 },
    { "guest" => 443, "host" => 443 },
  ]
end
# do not install a client, just generate the nodes
EXCLUDE_CLIENT = ENV["EXCLUDE_CLIENT"] || "false"
# generate the client, but do not prepare (ssh connectivity to all nodes) or generate the cluster
SKIP_PROVISION = ENV["SKIP_PROVISION"] || "false"
# generate the client, prepare the deployment (ssh connectiviry to all nodes) but do not proceed with the cluster geenration
SKIP_DEPLOYMENT = ENV["SKIP_DEPLOYMENT"] || "false"

# also install the kubernetes dashboard
INCLUDE_DASHBOARD = ENV["INCLUDE_DASHBOARD"] || "true"
DASHBOARD_FORWARDED_PORT = Integer(ENV['DASHBOARD_FORWARDED_PORT'] || "8888")
DASHBOARD_LB_PORT = Integer(ENV['DASHBOARD_LB_PORT'] || "443")
## network
IPS_PREFIX = ENV["IPS_PREFIX"] || "172.16.0."
NETMASK = ENV["NETMASK"] || "255.255.255.0"
CONTROLLERS_IP_START = Integer(ENV["CONTROLLERS_IP_START"] || 10)
WORKERS_IP_START = Integer(ENV["WORKERS_IP_START"] || 20)
LB_IP_SUFFIX = CONTROLLERS_IP_START + CONTROLLER_NODES + WORKERS_IP_START + WORKER_NODES + 1
CLIENT_IP_SUFFIX = LB_IP_SUFFIX + 1

## if not localhost, and install the dashboard
# we can get a certbot cert on lb
DOMAIN_NAME = ENV["DOMAIN_NAME"] || "localhost"

## images
LIBVIRT_IMAGE = ENV["LIBVIRT_IMAGE"] || "generic/ubuntu2004"
VBOX_IMAGE = ENV["VBOX_IMAGE"] || "ubuntu/focal64"
# env vars to pass to machines
PROVISION_ENV = {
  "CONTROLLER_NODES" => CONTROLLER_NODES,
  "WORKER_NODES" => WORKER_NODES,
  "IPS_PREFIX" => IPS_PREFIX,
  "LB_IP_SUFFIX" => LB_IP_SUFFIX,
  "CLIENT_IP_SUFFIX" => CLIENT_IP_SUFFIX,
  "CONTROLLERS_IP_START" => CONTROLLERS_IP_START,
  "WORKERS_IP_START" => WORKERS_IP_START,
  "DOMAIN_NAME" => DOMAIN_NAME,
  "INCLUDE_DASHBOARD" => INCLUDE_DASHBOARD,
  "DASHBOARD_FORWARDED_PORT" => DASHBOARD_FORWARDED_PORT,
  "DASHBOARD_LB_PORT" => DASHBOARD_LB_PORT,
}

# ssh provision
$before = <<SHELL
  sudo sed -i -E 's/^#?PasswordAuthentication no.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
  if [ -f /home/vagrant/.ssh/id_rsa ]; then 
      rm /home/vagrant/.ssh/id_rsa
  fi
  if [ -f /home/vagrant/.ssh/id_rsa.pub ]; then 
      rm /home/vagrant/.ssh/id_rsa.pub
  fi
  ssh-keygen -f /home/vagrant/.ssh/id_rsa -t rsa -q -N ''
  cat > /home/vagrant/.ssh/config <<EOF
Host #{IPS_PREFIX}*
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
EOF
chmod 600 /home/vagrant/.ssh/config && chown vagrant /home/vagrant/.ssh/config
if command -v systemctl  &> /dev/null; then
  if command -v apt &> /dev/null; then
    sudo systemctl restart ssh
  else
    sudo systemctl restart sshd
  fi
elif [ -f /etc/init.d/ssh ]; then
  sudo /etc/init.d/ssh restart
else
  sudo kill -HUP $(cat /var/run/sshd.pid)
fi
SHELL

# retrieve the insecure public key
PUBLIC_KEY = %x[ssh-keygen -y -f ~/.vagrant.d/insecure_private_key | tr -d '\n' ]

# start vagrant config
VAGRANTFILE_API_VERSION = "2"
Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|

  ############## global config start ################
  if Vagrant.has_plugin?("vagrant-hostmanager")
    # we handle /etc/hosts
    config.hostmanager.enabled = false
  end

  config.vm.box_check_update = false
  if Vagrant.has_plugin?("vagrant-vbguest")
    config.vbguest.auto_update = true
  end

  # no need to use /vagrant
  config.vm.synced_folder ".", "/vagrant", disabled: true

  # libvirt
  config.vm.provider "libvirt" do |libvirt, override|
    override.vm.box = LIBVIRT_IMAGE
    libvirt.graphics_type = "none"
    libvirt.video_type = "cirrus"
    libvirt.default_prefix = ""
  end
  # virtualbox
  config.vm.provider "virtualbox" do |vbox, override|
    override.vm.box = VBOX_IMAGE
  end
  ############## global config end ##################

  ############## definitions start ##################
  # load balancer
  config.vm.define "load-balancer" do |lb|
    lb.vm.network "private_network", ip: IPS_PREFIX + "#{LB_IP_SUFFIX}", netmask: NETMASK, hostname: true
    lb.vm.hostname = "load-balancer.kubernetes.local"
    LB_PORTS.each do|p|
      lb.vm.network "forwarded_port", guest: p["guest"], host: p["host"], host_ip: "0.0.0.0"
    end
    lb.vm.provider "virtualbox" do |vbox|
      vbox.name = "load-balancer"
      vbox.cpus = LB_CPUS
      vbox.memory = LB_MEMORY
    end
    lb.vm.provision "shell", privileged: false, inline: $before
  end
  # controllers
  (0..CONTROLLER_NODES - 1).each do |i|
    config.vm.define "controller-#{i}" do |controller|
      controller.vm.network "private_network", ip: IPS_PREFIX + "#{CONTROLLERS_IP_START + i}", netmask: NETMASK, hostname: true
      controller.vm.hostname = "controller-#{i}.kubernetes.local"
      controller.vm.provider "virtualbox" do |vbox|
        vbox.name = "controller-#{i}"
        vbox.memory = MEMORY_PER_CONTROLLER
        vbox.cpus = CPUS_PER_CONTROLLER
      end
      controller.vm.provider "libvirt" do |libvirt|
        libvirt.cpus = CPUS_PER_CONTROLLER
        libvirt.memory = MEMORY_PER_CONTROLLER
      end
      controller.vm.provision "shell", privileged: false, inline: $before
    end
  end
  # workers
  (0..WORKER_NODES - 1).each do |i|
      config.vm.define "worker-#{i}" do |worker|
        worker.vm.network "private_network", ip: IPS_PREFIX + "#{WORKERS_IP_START + i}", netmask: NETMASK, hostname: true
        worker.vm.hostname = "worker#{i}.kubernetes.local"
        worker.vm.provider "virtualbox" do |vbox|
          vbox.name = "worker-#{i}"
          vbox.memory = MEMORY_PER_WORKER
          vbox.cpus = CPUS_PER_WORKER
        end
        worker.vm.provider "libvirt" do |libvirt|
          libvirt.cpus = CPUS_PER_WORKER
          libvirt.memory = MEMORY_PER_WORKER
        end
        worker.vm.provision "shell", privileged: false, inline: $before
      end
  end

  if EXCLUDE_CLIENT.eql?("false")
    ## this one could be skipped,
    ## if we wish to install the required client tools (kubectl, ...) on the vagrant host
    # and run "provision" scripts either manually or with z2k.sh
    config.vm.define "client", primary: true do |client|
      client.vm.network "private_network", ip: IPS_PREFIX + "#{CLIENT_IP_SUFFIX}", netmask: NETMASK, hostname: true
      client.vm.hostname = "client.kubernetes.local"
      client.vm.provider "virtualbox" do |vbox|
        vbox.name  = "client"
        vbox.cpus = CLIENT_CPUS
        vbox.memory = CLIENT_MEMORY
      end
      client.vm.provider "libvirt" do |libvirt|
        libvirt.cpus = CLIENT_CPUS
        libvirt.memory = CLIENT_MEMORY
      end
      if SKIP_PROVISION.eql?("false")
        if File.exist?('.env')
          client.vm.provision "file",
          source: ".env",
          destination: "/home/vagrant/.env",
          preserve_order: true
        end
        client.vm.provision "file",
          source: "scripts/",
          destination: "/home/vagrant/",
          preserve_order: true
        client.vm.provision "file",
          source: "z2k.sh",
          destination: "/home/vagrant/z2k.sh",
          preserve_order: true
        client.vm.provision "shell",
          env: PROVISION_ENV,
          path: "provision.sh",
          args: SKIP_DEPLOYMENT.eql?("true") ? "--skip-deploy": "-",
          privileged: false,
          preserve_order: true
        end
    end
  end
  ############## definitions end ####################
end
