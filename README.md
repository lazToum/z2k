# Zero to Kubernetes

Generate a kubernetes cluster without/before using gcloud/aws or other cloud providers.

For educational purposes only, not meant to be used on production.

Based on (all credits to) [https://github.com/kelseyhightower/kubernetes-the-hard-way](https://github.com/kelseyhightower/kubernetes-the-hard-way)

## Extra

Optionally, also install and proxy the [Kubernetes Dashboard](https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/), and add use a certbot certificate on the load balancer.

A two controllers and two workers deployment result:
!["dashboard](./docs/dashboard.png "dashboard")

## Getting Started

### Slightly modified from the [original](https://github.com/kelseyhightower/kubernetes-the-hard-way) docs

- [01- Client tools](docs/01-client-tools.md)
- [02- Certificates](docs/02-certificates.md)
- [03- Configurations](docs/03-configs.md)
- ...

### [Scripts](./scripts)

- [./scripts/01-tools.sh](./scripts/01-tools.sh)
- [./scripts/02-certificates.sh](./scripts/02-certificates.sh)
- [./scripts/03-configs.sh](./scripts/03-configs.sh)
- [./scripts/04-etcd.sh](./scripts/04-etcd.sh)
- [./scripts/05-controllers.sh](./scripts/05-controllers.sh)
- [./scripts/06-workers.sh](./scripts/06-workers.sh)
- [./scripts/07-net.sh](./scripts/07-net.sh)
- [./scripts/08-smoke_tests.sh](./scripts/08-smoke_tests.sh) # N/A yet
- [./scripts/09-dashboard.sh](./scripts/09-dashboard.sh)


## Requirements:

- [Vagrant](https://www.vagrantup.com/)
- [vagrant-libvirt](https://github.com/vagrant-libvirt/vagrant-libvirt)

### All in one deployment

- Generate 2 controllers, 2 workers, 1 load-balancer and 1 client to generate the cluster:
 ```bash 
 vagrant up --provider=libvirt --no-parallel`
```
- Just generate vms (controllers, workers, load-balancer), in order to manually create the cluster:
 ```bash
EXCLUDE_CLIENT=true vagrant up --provider=libvirt --no-parallel
 ``` 
- Modify if needed [./.env.template](./.env.template) (either as env vars, or `cp .env.template .env`):
  - the number of controllers and workers
  - skip vagrant's provision step (manually generate the cluster using the [./scripts](./scripts))
  - ...
 