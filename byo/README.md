Rough idea of how the setup should look like:
```
 +------------
 |   YOU     |
 |./setup.sh ++
 +------------+
              |
              |                     +--------------+
              |                     |k8s-controller|
              +-------------------> |192.168.37.9  |
              |                     +--------------+
              |
              |                     +--------------+
              |                     |worker-node-0 |
              +-------------------> |192.168.37.10 |
              |                     +--------------+
              |
              |                     +--------------+
              |                     |worker-node-1 |
              +-------------------> |192.168.37.11 |
              |                     +--------------+
              |
              |                     +--------------+
              |                     |worker-node-2 |
              +-------------------> |192.168.37.12 |
                                    +--------------+
```

## How to prepare nodes

Download installer iso/img:

>**https://download.clearlinux.org/current/**

i.e. ```wget https://download.clearlinux.org/current/clear-19950-installer.iso.xz``` and unpack.

Create VM shell for each controller+worker, **enable nested virtualization features**, sized with approx:

  2x vCPU
  8GB RAM
  20-200GB of Disk (depending how serious you are)

Spin them up booting from the iso/img image, set IP settings if needed and install OS to disk.

**On each node do the following**
---------------------------------

Log into the console, login as 'root' and set the password (first and only time)

Install the following bundles:

```
swupd bundle-add sysadmin-basic network-basic containers-virt
```

Then enable root for ssh:

```
echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
systemctl enable sshd
systemctl start sshd
```

And enable/start docker:

```
systemctl enable docker
systemctl start docker
```

If you enabled nested virtualization as mentioned before, you should see cc-runtime as the default:

```
$ docker info | grep Runtime
Runtimes: cc-runtime runc
Default Runtime: cc-runtime
```

Create hosts file (needed kubelet iirc)

```
touch /etc/hosts
```

Set static IP (prolly optional)

```
mkdir -p /etc/systemd/network && vim /etc/systemd/network/50-static.network
```

Example of static IP on one of my (working) nodes:

```
[Match]
Name=ens192

[Network]
Address=192.168.37.11/24
Gateway=192.168.37.254
DNS=192.168.2.217
```

Set hostname (let's keep it tidy)

```
hostnamectl set-hostname k8s-controller
```

Disable swap

```
swapoff -a
```

## TODO

_Wrap all this stuff into packer/terraform/cloud-init/ovf... I'll get tuit_
_Clarify how to 'sed' kubelet.service to run with swap on_
