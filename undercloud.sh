#!/bin/bash

ssh-keygen

useradd stack
echo 'r3dh4t1!' | passwd stack --stdin
echo 'stack ALL=(root) NOPASSWD:ALL' | tee -a /etc/sudoers.d/stack
chmod 0440 /etc/sudoers.d/stack

sudo su - stack

echo "generate ssh key"
ssh-keygen

echo "Copy ssh from undercloud to host"
ssh-copy-id 192.168.0.1

echo "set hostname"
sudo hostnamectl set-hostname undercloud.example.com
sudo systemctl restart network.service

echo "Download repo"
sudo curl -o /etc/yum.repos.d/open.repo http://classroom/open.repo

echo "install screen"
sudo yum -y install screen

echo "configure /etc/hosts"
sudo yum -y install facter
ipaddr=$(facter ipaddress_eth1)
echo -e "${ipaddr}\tundercloud undercloud.example.com" | sudo tee -a /etc/hosts

echo "update the undercloud"
sudo yum update -y

echo "install packages"
sudo yum install -y python-tripleoclient \
  libvirt \
  libguestfs-tools \
  openstack-tripleo-heat-templates-compat \
  rhosp-director-images

echo "create undercloud config"
cat << EOF > ~/undercloud.conf
[DEFAULT]
local_ip = 172.16.0.1/24
undercloud_public_vip = 172.16.0.10
undercloud_admin_vip = 172.16.0.11
local_interface = eth0
masquerade_network = 172.16.0.0/24
dhcp_start = 172.16.0.20
dhcp_end = 172.16.0.120
network_cidr = 172.16.0.0/24
network_gateway = 172.16.0.1
discovery_iprange = 172.16.0.150,172.16.0.180
enable_telemetry = false
[auth]
EOF

echo "install undercloud"
openstack undercloud install

echo "check if catalog is installed fine"
openstack catalog list

echo "load stackrc"
. ~/stackrc

echo "unpack images"
mkdir ~/images
cd ~/images
tar xvf /usr/share/rhosp-director-images/overcloud-full.tar -C .
tar xvf /usr/share/rhosp-director-images/ironic-python-agent.tar -C .

echo "upload image"
openstack overcloud image upload

echo "go to host and generate the nodest.txt (see host.sh)."
echo "Hit enter when done"
read runhost

echo "generate the stackenv for instrospection"
cd ~
jq . << EOF > ~/instackenv.json
{
  "nodes": [
    {
      "name": "overcloud-ctrl01",
      "capabilities": "profile:control",
      "pm_addr": "192.168.0.1",
      "pm_password": "$(cat ~/.ssh/id_rsa)",
      "pm_type": "pxe_ssh",
      "mac": [
        "$(sed -n 1p ~/nodes.txt)"
      ],
      "pm_user": "stack"
    },
    {
      "name": "overcloud-ctrl02",
      "capabilities": "profile:control",
      "pm_addr": "192.168.0.1",
      "pm_password": "$(cat ~/.ssh/id_rsa)",
      "pm_type": "pxe_ssh",
      "mac": [
        "$(sed -n 2p ~/nodes.txt)"
      ],
      "pm_user": "stack"
    },
    {
      "name": "overcloud-ctrl03",
      "capabilities": "profile:control",
      "pm_addr": "192.168.0.1",
      "pm_password": "$(cat ~/.ssh/id_rsa)",
      "pm_type": "pxe_ssh",
      "mac": [
        "$(sed -n 3p ~/nodes.txt)"
      ],
      "pm_user": "stack"
    },
    {
      "name": "overcloud-compute01",
      "capabilities": "profile:compute",
      "pm_addr": "192.168.0.1",
      "pm_password": "$(cat ~/.ssh/id_rsa)",
      "pm_type": "pxe_ssh",
      "mac": [
        "$(sed -n 4p ~/nodes.txt)"
      ],
      "pm_user": "stack"
    },
    {
      "name": "overcloud-compute02",
      "capabilities": "profile:compute",
      "pm_addr": "192.168.0.1",
      "pm_password": "$(cat ~/.ssh/id_rsa)",
      "pm_type": "pxe_ssh",
      "mac": [
        "$(sed -n 5p ~/nodes.txt)"
      ],
      "pm_user": "stack"
    },
    {
      "name": "overcloud-ceph01",
      "capabilities": "profile:ceph-storage",
      "pm_addr": "192.168.0.1",
      "pm_password": "$(cat ~/.ssh/id_rsa)",
      "pm_type": "pxe_ssh",
      "mac": [
        "$(sed -n 6p ~/nodes.txt)"
      ],
      "pm_user": "stack"
    },
    {
      "name": "overcloud-ceph02",
      "capabilities": "profile:ceph-storage",
      "pm_addr": "192.168.0.1",
      "pm_password": "$(cat ~/.ssh/id_rsa)",
      "pm_type": "pxe_ssh",
      "mac": [
        "$(sed -n 7p ~/nodes.txt)"
      ],
      "pm_user": "stack"
    },
    {
      "name": "overcloud-ceph03",
      "capabilities": "profile:ceph-storage",
      "pm_addr": "192.168.0.1",
      "pm_password": "$(cat ~/.ssh/id_rsa)",
      "pm_type": "pxe_ssh",
      "mac": [
        "$(sed -n 8p ~/nodes.txt)"
      ],
      "pm_user": "stack"
    },
    {
      "name": "overcloud-networker",
      "capabilities": "profile:networker",
      "pm_addr": "192.168.0.1",
      "pm_password": "$(cat ~/.ssh/id_rsa)",
      "pm_type": "pxe_ssh",
      "mac": [
        "$(sed -n 9p ~/nodes.txt)"
      ],
      "pm_user": "stack"
    }
  ]
}
EOF

echo "validate and import instackenv"
openstack baremetal instackenv validate
openstack baremetal import --json instackenv.json

echo "set baremetal nodes as managed and instrospect"
for i in $(openstack baremetal node list -c Name -f value); do openstack baremetal node manage $i; done
openstack overcloud node introspect --all-manageable --provide

echo "create templates directory"
mkdir ~/templates

echo "create artifact for repo"
cd ~
sudo tar -czvf repo-artifact.tgz /etc/yum.repos.d/open.repo
sudo chown stack:stack repo-artifact.tgz
upload-swift-artifacts -f ~/repo-artifact.tgz \
  --environment ~/templates/deployment-artifacts.yaml

echo "create template for parameters: timezone"
cat << EOF > ~/templates/myparameters.yaml
parameter_defaults:
  TimeZone: 'EST'
EOF

echo "create template to disable ceilometer"
cat << EOF > ~/templates/disable_ceilometer.yaml
resource_registry:
  OS::TripleO::Services::MongoDb: OS::Heat::None
  OS::TripleO::Services::CeilometerApi: OS::Heat::None
  OS::TripleO::Services::CeilometerCollector: OS::Heat::None
  OS::TripleO::Services::CeilometerExpirer: OS::Heat::None
  OS::TripleO::Services::CeilometerAgentCentral: OS::Heat::None
  OS::TripleO::Services::CeilometerAgentNotification: OS::Heat::None
  OS::TripleO::Services::GnocchiApi: OS::Heat::None
  OS::TripleO::Services::GnocchiMetricd: OS::Heat::None
  OS::TripleO::Services::GnocchiStatsd: OS::Heat::None
  OS::TripleO::Services::AodhApi: OS::Heat::None
  OS::TripleO::Services::AodhEvaluator: OS::Heat::None
  OS::TripleO::Services::AodhNotifier: OS::Heat::None
  OS::TripleO::Services::AodhListener: OS::Heat::None
  OS::TripleO::Services::ComputeCeilometerAgent: OS::Heat::None
  OS::TripleO::Services::PankoApi: OS::Heat::None

parameter_defaults:
  ExtraConfig:
    neutron::notification_driver: noop
    nova::notification_driver: noop
    keystone::notification_driver: noop
    glance::notify::rabbitmq::notification_driver: noop
    cinder::ceilometer::notification_driver: noop
    manila::notification_driver: noop
    sahara::notify::notification_driver: noop
    barbican::api::notification_driver: noop
    ceilometer::notification_driver: noop
EOF

echo "deploy overcloud"
openstack overcloud deploy \
    --templates \
    --ntp-server 10.0.77.54 \
    --control-scale 3 \
    --compute-scale 2 \
    --ceph-storage-scale 3 \
    --neutron-tunnel-types vxlan \
    --neutron-network-type vxlan \
    --control-flavor control \
    --compute-flavor compute \
    --ceph-storage-flavor ceph-storage \
    -e ~/templates/disable_ceilometer.yaml \
    -e ~/templates/myparameters.yaml \
    -e ~/templates/deployment-artifacts.yaml

echo "validations"
echo "list stack failures"
openstack stack failures list overcloud

echo "list servers"
openstack server list

echo "load overcloudrc"
. ~/overcloudrc

echo "list compute services"
openstack compute service list

echo "list hypervisors"
openstack hypervisor list

echo "validate overcloud"

echo "create network external with management subnet"
neutron net-create management --router:external --provider:network_type flat --provider:physical_network datacentre

echo "create management subnet"
neutron subnet-create management 172.16.0.0/24 --name management_subnet --enable-dhcp=False --allocation-pool start=172.16.0.210,end=172.16.0.230 --dns-nameserver 8.8.8.8

echo "create internal network"
openstack network create internal

echo "create subnet in internal network"
neutron subnet-create internal 192.168.0.0/24 --name internal_subnet

echo "create router for internal network"
openstack router create internal_router

echo "set external network (management) as default route for internal router"
neutron router-gateway-set internal_router management

echo "add interface connected to the internal network"
neutron router-interface-add internal_router internal_subnet

echo "create security group for overcloud"
openstack security group create test

echo "register security key"
openstack keypair create --public-key ~/.ssh/id_rsa.pub stack

echo "create instance connected to the internal network"
internal_net=$(openstack network show internal -c id -f value)
openstack server create overcloud-test --security-group test --key-name stack --image cirros --flavor m1.tiny --nic net-id=$internal_net

echo "create floating ip from external (management) network"
openstack floating ip create management
openstack floating ip list

echo "copy floating ip and paste"
read floatingipnoted

echo "add floating ip to the instance"
openstack server add floating ip overcloud-test "${floatingipnoted}"

echo "add rules for icmp and ssh to the default security-group"
openstack security group rule create test --dst-port 22
openstack security group rule create test --proto icmp
