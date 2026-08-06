# Venu Helm charts

Production deployment chartlari va Argo CD bootstrap manifestlarining alohida reposi.
Botspace modeli ishlatiladi: chart shu repoda, environment values esa applicationning
o'z reposida saqlanadi.

## Tuzilma

- `charts/venu/` — Venu API, worker, PostgreSQL, backup va HTTPRoute.
- `charts/agents/` — Venu/Lattaputta agentlari, outreach, PostgreSQL va routes.
- `argocd/` — multi-source Argo CD `Application` manifestlari.

Image values:

- backend: `uzvenu/backend` -> `helm/values.yaml`
- agentlar: `charts/agents/values.yaml` (manual image release)

## Release oqimi

Backend CD image'ni immutable commit SHA bilan push qiladi, so'ng o'z reposidagi
`helm/values.yaml` qiymatini standart `GITHUB_TOKEN` bilan yangilaydi. Cross-repo PAT
yoki deploy token kerak emas. Argo CD chartni bu repodan, values'ni backend reposidan
o'qib render qiladi.

Agent image'i commit SHA bilan build/push qilinadi va `charts/agents/values.yaml`
image tagi yangilanadi. Agent release manual bo'lgani uchun cross-repo credential kerak emas.

## Lokal tekshiruv

Helm o'rnatilgan bo'lsa:

```bash
helm lint charts/venu
helm lint charts/agents
helm template venu charts/venu -f ../backend/helm/values.yaml >/dev/null
helm template agents charts/agents >/dev/null
```

Repo private. Argo CD `uzvenu/deploy`, `uzvenu/backend` va `uzvenu/chatbot` repolarini
o'qiy olishi kerak. Secret qiymatlari Gitga kiritilmaydi.
