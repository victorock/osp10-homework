#!/bin/bash

ssh-copy-id undercloud

for i in ctrl01 ctrl02 ctrl03 compute01 compute02 \
  ceph01 ceph02 ceph03 networker; \
  do virsh domiflist overcloud-$i | awk '$3 == "provisioning" {print $5};'; \
  done > /tmp/nodes.txt

echo "Copy nodes.txt to undercloud, enter password: \'r3dh4t1\!\'"
scp /tmp/nodes.txt stack@undercloud:~


echo "shutdown nodes"
for i in compute01 compute02 \
  ceph01 ceph02 ceph03 ctrl01 ctrl02 ctrl03 ; \
  do virsh shutdown overcloud-$i
  done
virsh shutdown undercloud

echo "reboot host to make sure that VMX is enabled"
echo "hit enter when rebooted"
read urebooted

echo "start nodes"
virsh start undercloud
for i in ctrl01 ctrl02 ctrl03 ceph01 ceph02 ceph03 \
  compute01 compute02 ; \
  do virsh start overcloud-$i
  done
