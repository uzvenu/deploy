# Standalone venu cluster

Latta Putta, Venu, The Antique, Venu CRM and Latta Putta's agents run on their own
Kubernetes on the venu server (`vm-v2-medium`, 195.26.230.199, netbird
100.100.141.147), separate from the legacy cluster whose control plane is
`de-vmmedium` (82.25.190.52).

The server is still a worker of the legacy cluster (`k3s-agent`), so a second
native k3s cannot run beside it. The venu cluster is k3s in Docker (k3d), with its
own network namespace, containerd, ArgoCD and gateway.

## Layout

| Path | What |
|---|---|
| `bootstrap/k3d.yaml` | Cluster definition, `/srv/venu-k8s/config/k3d.yaml` on the host |
| `bootstrap/ngf-values.yaml` | NGINX Gateway Fabric 2.6.2 Helm values (NodePort 30025) |
| `bootstrap/gateway.yaml` | `default/main-gateway`, which every chart route attaches to |
| `argocd/*.yaml` | The root Applications this cluster's ArgoCD owns; apply by hand |
| `reference/crm.yaml` | CRM Application reference only. The `venu` root creates it, do not apply |
| `bridges.yaml` | Links to the legacy cluster, venu side |
| `../legacy/bridges.yaml` | Links to this cluster, legacy side |

The `venu` root still generates the other brands' Applications through
`brandApplications` and `crmApplication` in `uzvenu/backend`
`helm/lattaputta-values.yaml`. Only `imageServiceApplication` is turned off here.

## Host

- Data: `/srv/venu-k8s/storage` is the node's `local-path` directory. Volumes moved
  from the legacy cluster keep their PV names and are pre-bound PVs with
  `hostPath.type: Directory`, so a pod never starts on an empty directory.
- Access: `vk` on the host is `kubectl --kubeconfig /srv/venu-k8s/config/kubeconfig`.
  The API listens on `127.0.0.1:6550` only. From a workstation, use
  `ssh -L 6550:127.0.0.1:6550 venu`.
- TLS stays on the host nginx (`/etc/nginx/sites-enabled/`). `venu.uz`, `the-antique.com`,
  `lattaputta.uz` and `crm.venu.uz` proxy to `127.0.0.1:31025`, which is the
  gateway NodePort 30025.
- PostgreSQL is the host's PostgreSQL 16. `pg_hba.conf` admits the k3d network
  `172.30.0.0/24` (docker network `venu-k3d`).
- The node container restarts with Docker (`--restart=unless-stopped`).

## Links to the legacy cluster

| Direction | Name | How |
|---|---|---|
| legacy → venu | `venu.iprogrammer.uz`, `venu-api.iprogrammer.uz`, `lattaputta.iprogrammer.uz` | DNS still points at 82.25.190.52. The legacy gateway routes them to `100.100.141.147:31025` (`venu-bridge/venu-cluster`) |
| legacy → venu | `venu-api.venu.svc:8080` for Motiv and Rocketpark | A selectorless legacy Service, pointing at `100.100.141.147:31080` → `venu/venu-api-legacy-bridge` NodePort 30080 |
| legacy → host | `venu.iprogrammer.uz/webhook/instagram` | Unchanged. This is the legacy `venu/instagram-openclaw-webhook` route to the host relay |
| venu → legacy | `codex-image-service.agent.svc:8091` | `venu-cluster-bridge.service` on the host: an SSH local forward `172.30.0.1:18091` → the legacy ClusterIP `10.43.177.40:8091`. Its key on `de-vmmedium` is restricted to that one `permitopen`. Netbird drops forwarded NodePort traffic between hosts, so a NodePort cannot be used |

The legacy cluster keeps the Codex image service, Motiv, Rocketpark, the shared
chatbot PostgreSQL (`argocd/agents.yaml` renders only that), monitoring and the image
registry. Images are still pulled from `registry.iprogrammer.uz`, which runs on the
legacy cluster.

## Rebuild from scratch

```sh
docker network create --driver bridge --subnet 172.30.0.0/24 --gateway 172.30.0.1 venu-k3d
k3d cluster create --config /srv/venu-k8s/config/k3d.yaml
docker update --restart=unless-stopped k3d-venu-server-0
k3d kubeconfig get venu > /srv/venu-k8s/config/kubeconfig
vk apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml
KUBECONFIG=/srv/venu-k8s/config/kubeconfig helm upgrade --install ngf \
  oci://ghcr.io/nginx/charts/nginx-gateway-fabric --version 2.6.2 \
  -n nginx-gateway --create-namespace -f bootstrap/ngf-values.yaml
vk apply -f bootstrap/gateway.yaml
vk create namespace argocd
vk apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.4.2/manifests/install.yaml
# Secrets: repository credentials in argocd, and each app namespace's env, registry
# and JWT Secrets. Copy them out of band; never commit them.
vk apply -f bridges.yaml
vk apply -f argocd/
```

## Rollback to the legacy cluster

1. Scale the venu cluster's workloads to 0, or delete its Applications with
   non-cascading deletion. Leaving both copies running duplicates Telegram polling
   and workers.
2. Move the volume directories back from `/srv/venu-k8s/storage/` to
   `/var/lib/rancher/k3s/storage/`. Use the same names: `<pv>_<namespace>_<claim>`.
3. On the legacy cluster, delete `venu-bridge` and the bridge `venu/venu-api`
   Service and EndpointSlice. Then re-apply `argocd/agents.yaml` without its
   `parameters`, plus these root Applications from git history:
   `clusters/venu/argocd/venu.yaml` without the parameter, and `venu-frontend.yaml`.
4. Point the host nginx `proxy_pass` back at `127.0.0.1:30025` and reload nginx.
