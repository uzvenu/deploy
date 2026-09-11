# Brand deployment model

Each marketplace brand is an independent GitOps instance. Images and charts are reused; databases, storage, runtime identity and credentials are not.

## Isolation boundary

A brand receives:

- one namespace for API, worker, storefront, PostgreSQL, object storage PVC and backup PVC;
- one agent namespace with its own PostgreSQL and HTTP-only customer agent;
- one backend values file in the backend repository;
- one agent values file in the agent repository;
- one storefront values file in the frontend repository;
- three Argo CD Applications that combine the shared charts with those values;
- a root application's `brandApplications.items` entry that bootstraps those child Applications through GitOps;
- out-of-band Secrets named only by the values files.

Do not copy database/PVC contents, JWT keys, internal service tokens, storage credentials or Telegram bot identities between brands.

## Shared charts

- `charts/venu`: API, worker, migration, PostgreSQL, storage PVC, backup and API route.
- `charts/agents`: agent, agent PostgreSQL and cross-namespace `ReferenceGrant`.
- `charts/storefront`: branded Next.js storefront and public route.

The application repositories own immutable image tags. Their CD workflows update every `helm/*values.yaml` file, so all brand instances promote the same validated code while retaining independent runtime configuration.

Every backend instance keeps its in-namespace API Service named `venu-api`. Next.js rewrites bake `http://venu-api:8080` into the shared image at build time; identical Service names remain isolated because Kubernetes DNS resolves them inside each storefront namespace.

## Adding a brand

Assume the brand slug is `acme`.

1. Add `backend/helm/acme-values.yaml`, based on `helm/venu-market-values.yaml`.
2. Add `agent/helm/acme-values.yaml`, based on `helm/venu-market-values.yaml`.
3. Add `frontend/helm/acme-values.yaml`, based on `helm/venu-market-values.yaml`.
4. Add three Argo Applications under `argocd/`, targeting namespaces `acme` and `acme-agent`, then add matching entries to the root backend values `brandApplications.items`. The root Argo Application creates the children automatically; no workload `kubectl apply` is used.
5. Create the namespaces and out-of-band Secrets before enabling the root bootstrap entries.
6. Use a fresh PostgreSQL password, JWT keypair, NextAuth secret, storage signing key and backend-agent service token.
7. Keep `APP_AUTH_CUSTOMER_OTP_ENABLED=false` and `worker.enabled=false` until the brand has its own Eskiz credentials and moderated SMS templates. Never borrow another brand's provider credentials.
8. Keep `storage.enabled=false` and `backup.enabled=false` while `api.enabled=false`. The `local-path` class binds a claim only on first mount, so a claim with no consumer stays `Pending` and holds the Argo Application in `Progressing`. Enable all three together.
9. Configure frontend runtime identity in its Secret:
   - `BRAND_ID=acme`
   - `BRAND_NAME=Acme`
   - `SITE_URL=https://acme.example`
   - `BRAND_PRIMARY_COLOR=#rrggbb`
   - `BRAND_PRIMARY_FOREGROUND=#rrggbb`
   - `BRAND_RING_COLOR=#rrggbb`
   - optional root-relative asset overrides such as `BRAND_LOGO_PATH=/brands/acme/logo.png`
10. Configure backend identity with matching `APP_BRAND_*` values.
11. Configure the agent with matching `BRAND_*`, `CATALOG_API_BASE`, `CATALOG_SITE_BASE` and a fresh `DATABASE_URL`.
12. Run `helm lint` and `helm template` for all charts with real values, then push. The root app-of-apps bootstrap creates the child Applications and all workloads remain GitOps-managed.
13. Verify readiness, health endpoints and an empty/fresh database before changing DNS or the external load balancer.

Unknown frontend `BRAND_ID` values are supported without TypeScript changes when `BRAND_NAME`, `SITE_URL`, `BRAND_LOGO_PATH` and `BRAND_PRIMARY_COLOR` are supplied. Logo paths may be root-relative bundled assets or absolute HTTPS URLs; custom brands do not inherit another brand's contacts, links or images. Palette changes require only a Secret update and controlled storefront restart.

## Venu production instance

The Venu instance uses:

- application namespace: `venu-market`;
- agent namespace: `venu-market-agent`;
- storefront host: `venu.uz`;
- API host: `api.venu.uz`;
- logo primary color: `#EC1D38`.

It starts with fresh PostgreSQL and storage PVCs. Database, media and daily logical backups are separate from Latta Putta; the local-path backup still shares the cluster node's failure domain, so off-node backup is required before valuable production data accumulates. No Latta Putta rows are imported.
