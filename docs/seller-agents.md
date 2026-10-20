# Seller agent chart wiring

Only non-secret configuration is supplied by these charts. Application repositories
own brand values and immutable image tags; this change does not release application
code, provision Secrets, or register seller accounts.

## Backend policy

`productImport.sellerImageMode` accepts `generate` or `provided`.
`productImport.sellerGeneratedImageRoles` is an ordered, unique list of
`product_only`, `mannequin`, and/or `model`; `generate` requires at least one.
API and worker receive `APP_PRODUCT_IMPORT_SELLER_IMAGE_MODE` and
`APP_PRODUCT_IMPORT_SELLER_GENERATED_IMAGE_ROLES`. Roles use **CSV**, not JSON:
Viper unmarshals the string slice, and the backend explicitly handles an empty
string as an empty list (rather than keeping its defaults).

Current proposed application values:

| Brand | Seller image mode | Generated roles |
| --- | --- | --- |
| Latta Putta | generate | product_only,mannequin,model |
| Venu | generate | product_only |
| The Antique | provided | empty |

The migration Job is unchanged: it does not execute import policy, and the config
loader's defaults form a valid policy. Panel import switches remain independent;
Venu's panel image mode/search and image-AI-disabled settings are not rewritten by
seller policy. Runtime generation/provider credentials and role handling must be
supported by the backend image released with these values.

## Process isolation

- `sellerAgent.enabled: false`: no seller workload.
- Enabled, empty `sellerAgent.secretName`: existing combined legacy modes remain
  `telegram,instagram,whatsapp,seller`. An enabled legacy agent is required.
  `sellerAgent.extraEnv` is included in that process and overrides
  `legacyAgent.extraEnv` by name. Latta Putta uses this path.
- Enabled, nonempty `sellerAgent.secretName`: a dedicated one-replica `Recreate`
  Deployment runs **only** `-mode seller`. Legacy modes exclude seller; modern
  modes must not include seller. No customer Secret or customer token fallback is
  used. Ensure the seller token is not being polled by any other process.

The dedicated seller inherits only `BRAND_NAME`, `BRAND_SITE`,
`BRAND_PRODUCT_PATH`, `BRAND_RESPONSE_LANGUAGE`, `CATALOG_PROVIDER`,
`CATALOG_API_BASE`, and `CATALOG_SITE_BASE` from `modernAgent.extraEnv`.
`sellerAgent.extraEnv` overrides these by name. Customer CRM, KB, Telegram and
Google credentials are not copied. No customer Secret is used for datasource
credentials either.

Seller-only mode does not start an HTTP listener. It intentionally has no Service,
HTTPRoute or TCP/HTTP probes; port configuration would not create a listener.
Kubernetes process status is not a Telegram readiness check: the current binary
can remain idle if `SELLER_TELEGRAM_BOT_TOKEN` is missing. Confirm successful account
loading and polling in a controlled release; do not send live test messages.

## Out-of-band Secret requirements (names only)

Create/verify these in the **agent workload's namespace**, not the backend namespace:

- The Antique: `theantique-seller-agent-env` (application destination `theantique-agent`).
- Venu: `venu-seller-agent-env` (application destination `venu-market-agent`).
- Latta Putta retains its existing combined legacy environment Secret.

Required for each dedicated seller:

- `SELLER_TELEGRAM_BOT_TOKEN`: dedicated seller Bot API token, not the customer bot.
- `SELLER_AGENT_WORKER_TOKEN`: must match the brand backend's worker-token config.
- LLM provider credential (`DEEPSEEK_API_KEY` with the current default provider).
- `OPENAI_API_KEY` for the current configured embedding provider at shared startup;
  supply any explicitly configured provider overrides and their credentials.

Optional/conditional:

- `DATABASE_URL`: dedicated authorized agent session datasource for persistent
  history. If omitted, the application uses in-memory history; do not copy customer
  database credentials implicitly.
- `SELLER_TELEGRAM_BUSINESS` plus `SELLER_TELEGRAM_BUSINESS_OWNER_IDS` if Business
  integration is intended; keep disabled unless configured and authorized.

The public `SELLER_AGENT_CONTROL_BASE_URL` must be the backend **origin**, without
`/api/v1`; clients add their own paths. Backend account mapping/authorized shops
must already exist. `SELLER_IMPORT_IMAGE_MODE` must agree with backend seller
policy. Secret existence, key contents, token uniqueness, provider billing and
backend authorization cannot be proven with Helm lint/template.

## Networking

Existing agent/marketplace policies are ingress-only and do not deny seller egress.
No seller Service is exposed, so no ingress allowance is added. Current database
policy allows ingress without filtering pod labels; no selector change is needed.
If namespace-wide default-deny is introduced, explicitly permit DNS, the brand
backend, the configured session database, and required Telegram/LLM/embedding/
image HTTPS destinations. Image generation normally runs in the backend worker,
not the seller pod; preserve its provider/image-service connectivity separately.

## Validation

Run `ruby tests/seller-wiring.rb` from `deploy/`. Tests render real application
values, assert policy and Secret isolation, preserve combined mode, and reject
invalid policies and duplicate seller mode. Lint/render marketplace and agent
with all three brand files, and storefront with all three available real brand
files. Latta Putta's storefront Argo application still uses raw Kustomize
(`argocd/venu-frontend.yaml`); its application repository also supplies a Helm
values file for chart validation.

Modern/admin import policy comes only from `modernAgent.extraEnv`, independently
of the dedicated seller policy. All three brand values explicitly supply
`SELLER_IMPORT_IMAGE_MODE` there. Modern and combined legacy environments merge
whole entries by name: chart defaults first, process extraEnv second, combined
seller extraEnv last. The last entry wins without duplicate names or mixing
`value` and `valueFrom` fields.
