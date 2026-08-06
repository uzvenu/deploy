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
- agentlar: `charts/agents/values.yaml` (chatbot CD yangilaydi)

## Release oqimi

Backend CD image'ni immutable commit SHA bilan push qiladi, so'ng o'z reposidagi
`helm/values.yaml` qiymatini standart `GITHUB_TOKEN` bilan yangilaydi. Cross-repo PAT
yoki deploy token kerak emas. Argo CD chartni bu repodan, values'ni backend reposidan
o'qib render qiladi.

Chatbot CD image'ni commit SHA bilan build/push qiladi va `charts/agents/values.yaml`
image tagini yangilaydi. Cross-repo yozish uchun chatbot Actions'da faqat shu repoga
write huquqli `DEPLOY_REPO_TOKEN` ishlatiladi.

## Lokal tekshiruv

Helm o'rnatilgan bo'lsa:

```bash
helm lint charts/venu
helm lint charts/agents
helm template venu charts/venu -f ../backend/helm/values.yaml >/dev/null
helm template agents charts/agents >/dev/null
```

Chart repo public, chunki unda secret qiymatlari yo'q; private backend values reposi
Argo CD repository credential orqali o'qiladi. Secret qiymatlari Gitga kiritilmaydi.
