# Venu Helm charts

Production deployment chartlari va Argo CD bootstrap manifestlarining alohida reposi.
Botspace modeli ishlatiladi: chart shu repoda, environment values esa applicationning
o'z reposida saqlanadi.

## Tuzilma

- `charts/venu/` — Venu API, worker, PostgreSQL, backup va HTTPRoute.
- `charts/agents/` — Venu/Lattaputta agentlari, outreach, PostgreSQL va routes.
- `charts/motiv-agent/` — mustaqil Motiv Deployment, Service va HTTPRoute.
- `argocd/agents.yaml` — Venu/Latta Putta Application.
- `argocd/motiv-agent.yaml` — Motiv Application.

Image values:

- backend: `uzvenu/backend` -> `helm/values.yaml`
- Venu/Latta Putta agentlari: `uzvenu/chatbot` -> `helm/values.yaml`
- Motiv: `uzvenu/support` -> `helm/values.yaml`

## Release oqimi

Backend CD image'ni immutable commit SHA bilan push qiladi, so'ng o'z reposidagi
`helm/values.yaml` qiymatini standart `GITHUB_TOKEN` bilan yangilaydi. Cross-repo PAT
yoki deploy token kerak emas. Argo CD chartni bu repodan, values'ni backend reposidan
o'qib render qiladi.

Chatbot CD image'ni commit SHA bilan build/push qiladi va o'z reposidagi
`helm/values.yaml` image tagini standart `GITHUB_TOKEN` bilan yangilaydi. Argo CD
`charts/agents` chartini shu external values source bilan render qiladi. Motiv CD esa
`uzvenu/support/helm/values.yaml` tagini yangilaydi va `motiv-agent` Application
`charts/motiv-agent`ni shu values bilan render qiladi; cross-repo deploy token kerak emas.

## Motiv Application split

`motiv-agent`ni eski `agents` Application'dan downtime'siz ajratish tartibi
`MOTIV_SPLIT.md`da yozilgan. Eski Application auto-prune yoqilgan holda chartdan
Motiv resurslarini olib tashlab, yangi Application'ni keyin yaratish taqiqlanadi:
Deployment, Service va HTTPRoute vaqtincha o'chib ketadi.

## Multi-source cutover va rollback

Cutover tartibi:

1. Avval `uzvenu/chatbot` `main` branchiga `helm/values.yaml` va yangi CD workflow'ni chiqaring.
2. `argocd` namespace'dagi `chatbot-repo` credential'i private values repo'ni o'qishini tekshiring.
3. Keyin shu repodagi `argocd/agents.yaml` multi-source o'zgarishini chiqaring va Application manifestini yangilang.

Deploy manifesti birinchi chiqsa, hali mavjud bo'lmagan `$values/helm/values.yaml` sabab Argo CD render xatosi beradi.
Rollback qilishda avval `charts/agents/values.yaml` tagini `chatbot/helm/values.yaml`dagi joriy tag bilan tenglashtiring, keyin `agents` Application'ni single-source holatiga qaytaring. Bu eski chart default tagiga kutilmagan rollbackni oldini oladi.

## Lokal tekshiruv

Helm o'rnatilgan bo'lsa:

```bash
helm lint charts/venu
helm lint charts/agents -f ../agent/helm/values.yaml
helm lint charts/motiv-agent -f ../chatbot/helm/values.yaml
helm template venu charts/venu -f ../backend/helm/values.yaml >/dev/null
helm template agents charts/agents -f ../agent/helm/values.yaml >/dev/null
helm template motiv-agent charts/motiv-agent -f ../chatbot/helm/values.yaml >/dev/null
```

Chart repo public, chunki unda secret qiymatlari yo'q; private backend va chatbot values repolari
Argo CD repository credential orqali o'qiladi. Secret qiymatlari Gitga kiritilmaydi.
