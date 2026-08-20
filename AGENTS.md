# GitOps repository rules

- `charts/venu`, `charts/agents` va `charts/motiv-agent` production Helm source-of-truth hisoblanadi.
- Backend image tagi `backend/helm/values.yaml`da, Venu/Latta Putta agent tagi `agent/helm/values.yaml`da, Motiv tagi esa `chatbot/helm/values.yaml`da saqlanadi. Har bir application CD o'z repo values faylini standart `GITHUB_TOKEN` bilan yangilaydi.
- Secret qiymatlarini Gitga yozmang; faqat Secret nomlari chartlarda bo'lishi mumkin.
- Live tracked resurslarni `kubectl patch/apply/set image` bilan o'zgartirmang.
- Har o'zgarishdan keyin uchala chart uchun `helm lint` va real values bilan `helm template` ishlashi shart.
- Image taglari immutable commit SHA bo'lsin; chart values'da `latest` ishlatmang.
- Namespace'lar Argo destination orqali aniq: Venu uchun `venu`, agentlar uchun `agent`.
- Destructive storage yoki database o'zgarishi backup va rollback rejasiz qilinmaydi.

## Real klasterda `kubectl` xavfsizligi

- `~/.kube/config` real production yoki boshqa loyihalar klasteriga ulangan deb hisoblang. Har qanday tekshiruvdan oldin `kubectl config current-context`, `kubectl cluster-info` va target namespace'ni tekshiring; namespaced buyruqlarda `-n <namespace>`ni doim ochiq yozing.
- Tekshiruvni faqat read-only buyruqlardan boshlang: `get`, `describe`, `logs`, `events` va `auth can-i`. Dalilsiz yozuvchi buyruq ishlatmang.
- `delete`, `replace --force`, `scale --replicas=0`, `drain`, `cordon`, `taint`, PVC/Secret/namespace o'chirish, migration rollback yoki DB yozuvi faqat foydalanuvchining alohida va aniq tasdig'i bilan bajariladi. `kubectl apply --prune` taqiqlangan.
- Tracked Deployment/Service/HTTPRoute va image taglarini live klasterda `patch`, `apply` yoki `set image` bilan o'zgartirmang; o'zgarish GitOps source-of-truth orqali deploy qilinadi.
- Secret qiymatini `get -o yaml/json`, `describe`, `printenv` yoki log orqali chiqarmang. Faqat key nomlarini ko'rish mumkin; Secret yangilanganda mavjud boshqa key'larni saqlang.
- Ruxsat etilgan out-of-band Secret/env yangilanishidan keyin faqat shu env'ni o'qiydigan workload uchun kontrolli `rollout restart` mumkin; rollout, readiness, restart count, health endpoint va relevant loglar tekshirilishi shart.
- Production tekshiruvida payment, booking, SMS, Telegram login kodi yoki boshqa tashqi/pulli side effect yaratmang. Bunday sinov zarur bo'lsa, oldin foydalanuvchidan aniq tasdiq oling.
