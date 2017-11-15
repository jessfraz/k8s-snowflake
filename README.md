# k8s-snowflake

[![Build Status](https://travis-ci.org/jessfraz/k8s-snowflake.svg?branch=master)](https://travis-ci.org/jessfraz/k8s-snowflake)

Configs and scripts for bootstrapping an opinionated Kubernetes cluster anywhere.

Except it's my _snowflake opinionated k8s distro_ :)

> **NOTE:** current support is only for Azure and Google Cloud.

## Provisioning

These are **opinionated scripts**. If you don't like my opinions maybe consider
using one of the hundred-thousand other tools for provisioning a cluster.

I literally made this _because_ I didn't like the opinion of other things... so
here we are. :P

I purposely tried to keep this as minimal and simple as possible from the OS
base up.

### Base OS

Every node uses [Intel's Clear Linux](https://clearlinux.org/) as the base.
This is for reasons of security and performance. If you would like to learn
more on that you should click the link to their site.

### Encrypted `etcd` secret data at rest

Data is encrypted with `aescbc`. You verify it's encrypted by following [these
instructions](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/#verifying-that-data-is-encrypted).

### RBAC and Pod Security Policies

Kubernetes is installed with [`RBAC`](https://kubernetes.io/docs/admin/authorization/rbac/)
and is set up with a few roles and bindings that map to pod security policies.

There is a [restricted pod security policy](etc/pod-security-policy-restricted.yaml)
which does not allow running
privileged pods and does not allow privilege escalation which is through the linux
`no_new_privs` flag.

There is also a [permissive pod security
policy](etc/pod-security-policy-permissive.yaml).

There are two cluster role bindings created (which grant permissions across
namespaces):

- `restricted`: cannot create privileged pods, cannot escalate privileges,
  cannot run containers as root, cannot use the host network, IPC or PID
  namespace
- `privileged`: can create pods that are privileged and use the privileged pod
  security policy

### Container Runtime

The cluster uses [`cri-containerd`](https://github.com/kubernetes-incubator/cri-containerd)
with [`runc`](https://github.com/opencontainers/runc) as the container
runtime.

### Networking

The cluster uses [`cilium`](https://github.com/cilium/cilium)
as a networking plugin. I like cilium because it uses BPF and XDP and their
design is something I could wrap my head around. You should checkout their repo
it's one of the cleanest implementations I have seen.

## Azure

Make sure you have the `az` tool installed. You can find instructions on
downloading that
[here](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest).

Make sure you are logged in.

To provision your cluster, clone this repo and run:

```console
$ ./azure/setup.sh
```

The script automatically sets up an `admin` user with kubeconfig locally so you
should be able to just run `kubectl` after!

> **NOTE:** if you want to change the number of nodes, etc checkout the
> environment variables at the top of [`azure/setup.sh`](azure/setup.sh).

## Google Cloud

Make sure you have the `gcloud` tool installed. You can find instructions on
downloading that
[here](https://cloud.google.com/sdk/downloads).

Make sure you are logged in.

To provision your cluster, clone this repo and run:

```console
$ VM_USER="your_ssh_user" ./gcloud/setup.sh
```

The script automatically sets up an `admin` user with kubeconfig locally so you
should be able to just run `kubectl` after!

> **NOTE:** if you want to change the number of nodes, etc checkout the
> environment variables at the top of [`gcloud/setup.sh`](gcloud/setup.sh).

## Acknowledgements

Thanks to [@kelseyhightower](https://github.com/kelseyhightower) for
[kubernetes-the-hard-way](https://github.com/kelseyhightower/kubernetes-the-hard-way)
which helped a lot of this.

If you are wondering why I didn't use something like `cloud-init` it's because
Clear Linux has a pretty weirdly behaving version of `cloud-init` and I love
bash, m'kay.
