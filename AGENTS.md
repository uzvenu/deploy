# GitOps repository rules

- `charts/venu` va `charts/agents` production Helm source-of-truth hisoblanadi.
- Backend image tagi `backend/helm/values.yaml`da; manual agent tagi `charts/agents/values.yaml`da saqlanadi.
- Secret qiymatlarini Gitga yozmang; faqat Secret nomlari chartlarda bo'lishi mumkin.
- Live tracked resurslarni `kubectl patch/apply/set image` bilan o'zgartirmang.
- Har o'zgarishdan keyin ikkala chart uchun `helm lint` va real values bilan `helm template` ishlashi shart.
- Image taglari immutable commit SHA bo'lsin; chart values'da `latest` ishlatmang.
- Namespace'lar Argo destination orqali aniq: Venu uchun `venu`, agentlar uchun `agent`.
- Destructive storage yoki database o'zgarishi backup va rollback rejasiz qilinmaydi.
