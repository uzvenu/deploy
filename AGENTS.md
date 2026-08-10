# GitOps repository rules

- `charts/venu`, `charts/agents` va `charts/motiv-agent` production Helm source-of-truth hisoblanadi.
- Backend image tagi `backend/helm/values.yaml`da, Venu/Latta Putta agent tagi `agent/helm/values.yaml`da, Motiv tagi esa `chatbot/helm/values.yaml`da saqlanadi. Har bir application CD o'z repo values faylini standart `GITHUB_TOKEN` bilan yangilaydi.
- Secret qiymatlarini Gitga yozmang; faqat Secret nomlari chartlarda bo'lishi mumkin.
- Live tracked resurslarni `kubectl patch/apply/set image` bilan o'zgartirmang.
- Har o'zgarishdan keyin uchala chart uchun `helm lint` va real values bilan `helm template` ishlashi shart.
- Image taglari immutable commit SHA bo'lsin; chart values'da `latest` ishlatmang.
- Namespace'lar Argo destination orqali aniq: Venu uchun `venu`, agentlar uchun `agent`.
- Destructive storage yoki database o'zgarishi backup va rollback rejasiz qilinmaydi.
