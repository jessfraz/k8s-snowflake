#!/bin/bash
#
# This script is run by vagrant on startup.  Do not run it.
#
set -e
set -o pipefail

if grep vagrant /home/vagrant/.ssh/authorized_keys > /dev/null; then
  echo "Disabling swap"
  swapoff -a
  echo "Setting noop scheduler"
  echo noop > /sys/block/sda/queue/scheduler
  echo  "Disabling IPv6"
  echo "net.ipv6.conf.all.disable_ipv6 = 1
        net.ipv6.conf.default.disable_ipv6 = 1
        net.ipv6.conf.lo.disable_ipv6 = 1" >> /etc/sysctl.conf
  sysctl -p
fi
