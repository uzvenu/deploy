# Latta Putta / Venu split — phase 1 scaffold

## Scope and safety contract

The live stack is Latta Putta even though its Kubernetes resources, namespace,
Secrets, PVCs and public hosts currently use `venu` names. Phase 1 does not rename,
delete, move or recreate any of those resources.

This phase only parameterizes the existing charts. Chart defaults deliberately
preserve the current rendered object identities and references. The files under
`charts/*/examples/future-*-values.yaml` are design examples, start with
`enabled: false`, use non-routable `.example.invalid` hosts where applicable, and
are not referenced by any Argo CD Application.

Venu is a future new stack. Creating its namespaces, Argo Applications, Secrets,
databases, storage, routes, DNS or external integrations is outside phase 1.

## Current default compatibility contract

`charts/venu/values.yaml` keeps these current resources and references:

- `venu-api`, `venu-worker`, `venu-migrate`;
- `postgres`, `postgres-data`, `postgres-backups`, `postgres-backup`;
- `venu-env`, `venu-jwt`, `venu-postgres`, `venu-registry`;
- `venu-api.iprogrammer.uz` through `default/main-gateway`;
- `/ai` to `venu-agent` in namespace `agent`;
- API agent URL `http://venu-agent.agent.svc.cluster.local:8080`;
- backup prefix `venu-`, schedule `0 22 * * *`, retention 7 days;
- API storage remains `emptyDir` while `api.storageClaimName` is empty.

`charts/agents/values.yaml` keeps these current resources and references:

- `venu-agent`, `lattaputta-agent`, `lattaputta-outreach`;
- partner reminders remain disabled;
- `postgres`, `postgres-data`, `postgres-init` and logical databases
  `venu`, `lattaputta`, `motiv`;
- `venu-agent-env`, `lattaputta-agent-env`, `lattaputta-outreach-env`;
- `agents-postgres`, `google-creds`, `venu-registry`;
- `lattaputta.iprogrammer.uz` through `default/main-gateway`;
- `venu-httproute-to-agents` still grants only namespace `venu`.

The existing Argo manifests remain unchanged and continue to consume the same
application-owned values files:

- `argocd/venu.yaml` -> `backend/helm/values.yaml`;
- `argocd/agents.yaml` -> `agent/helm/values.yaml`.

## Parameterized surfaces

Backend chart:

- component/resource names and `app.kubernetes.io/part-of`;
- registry, runtime, JWT, PostgreSQL and optional storage Secret/PVC references;
- PostgreSQL Service/PVC/storage settings;
- backup name/PVC/schedule/prefix/retention;
- API hostname, Gateway and agent backend reference;
- chart-level `enabled` guard.

Agents chart:

- modern agent, legacy agent, outreach and reminder names/Secrets;
- per-component enabled guards;
- registry and Google credential Secret names;
- PostgreSQL names/Secret/PVC/storage and initial logical database list;
- public hostname, Gateway and Service target;
- ReferenceGrant name/source namespace;
- chart-level `enabled` guard.

Changing a selector-backed component name replaces that workload. Phase 1 keeps
all defaults unchanged; future migrations must use blue/green resources and the
ownership-transfer procedure rather than changing live values in place.

## Future values examples

- `charts/venu/examples/future-lattaputta-values.yaml`
- `charts/venu/examples/future-venu-values.yaml`
- `charts/agents/examples/future-lattaputta-values.yaml`
- `charts/agents/examples/future-venu-values.yaml`

The `0000000` image tag is an intentionally unavailable immutable SHA sentinel.
A future promotion must replace it with a real immutable commit SHA before the
example can be enabled.

The examples contain Secret object names only, never Secret values. Latta Putta
production data and credentials must not be copied into future Venu.

## Required validation before merge or future enablement

Run with the current application-owned values:

```bash
helm lint charts/venu -f ../backend/helm/values.yaml
helm template venu charts/venu -f ../backend/helm/values.yaml
helm lint charts/agents -f ../agent/helm/values.yaml
helm template agents charts/agents -f ../agent/helm/values.yaml
```

The first two rendered outputs must retain the compatibility contract above.

Disabled examples must render no Kubernetes objects:

```bash
helm template future-lattaputta charts/venu \
  -f charts/venu/examples/future-lattaputta-values.yaml
helm template future-venu charts/venu \
  -f charts/venu/examples/future-venu-values.yaml
helm template future-lattaputta-agent charts/agents \
  -f charts/agents/examples/future-lattaputta-values.yaml
helm template future-venu-agent charts/agents \
  -f charts/agents/examples/future-venu-values.yaml
```

Before any later Argo Application is added, also verify unique rendered
`(apiVersion, kind, namespace, metadata.name)` identities, immutable image tags,
namespace-local Secrets/PVCs, exact cross-namespace ReferenceGrants, and an Argo
diff with no current resource deletion or ownership overlap.

## Explicitly deferred

- no new Argo CD Application;
- no namespace creation;
- no frontend/mobile source or deployment changes;
- no DNS, TLS, HTTPRoute or callback changes;
- no Secret creation or copying;
- no database/PVC/storage migration;
- no decision about retiring the existing legacy `lattaputta-agent`;
- no Motiv database ownership change.
