# Motiv agentni alohida Argo CD Application'ga ajratish

## Yakuniy ownership

- `agents` Application (`charts/agents`): `venu-agent`, `lattaputta-agent`, outreach, PostgreSQL va umumiy ReferenceGrant.
- `motiv-agent` Application (`charts/motiv-agent`): faqat Motiv Deployment, Service va HTTPRoute.
- `motiv-agent-env`, `motiv-agent-token`, `google-creds` va `venu-registry` Secretlari out-of-band qoladi; chart ularning qiymatini boshqarmaydi.
- PostgreSQL/PVC eski `agents` Application'da qoladi va migratsiyada unga tegilmaydi.

## Nega kontrolli cutover kerak

Eski `agents` Application'da automated prune yoqilgan. Deploy repo push qilingach u
Motiv resurslarini eski chartdan yo'qolgan deb ko'rib, yangi Application ularni qabul
qilishidan oldin o'chirishi mumkin. Shu sabab cutover vaqtida eski Application auto-sync'i
vaqtincha pauza qilinadi.

## Cutover

Bu buyruqlarni production klaster konteksti va `agent` namespace tekshirilgandan keyin
inson operator bajaradi. Kod agenti commit/push yoki deploy qilmaydi.

1. Context, ruxsat va joriy health:

   ```bash
   kubectl config current-context
   kubectl cluster-info
   kubectl auth can-i patch applications.argoproj.io -n argocd
   kubectl get application agents -n argocd
   kubectl get deployment,service,httproute -n agent
   ```

2. Eski `agents` Application auto-sync'ini vaqtincha o'chiring va pauza haqiqatan
   kuchga kirganini tekshiring:

   ```bash
   argocd app set agents --sync-policy none
   kubectl get application agents -n argocd \
     -o jsonpath='{.spec.syncPolicy.automated}{"\n"}{.status.operationState.phase}{"\n"}'
   ```

   `.spec.syncPolicy.automated` bo'sh bo'lishi va ishlayotgan sync operation bo'lmasligi
   shart. `Running` operation bo'lsa tugashini kuting. Shu gate o'tmasdan push qilmang.

3. Ushbu deploy o'zgarishini `uzvenu/deploy@master`ga chiqaring. Eski Application
   pauzada qolganini pushdan keyin yana tekshiring.

4. Yangi Application'ni yarating va sync qiling:

   ```bash
   kubectl apply -f argocd/motiv-agent.yaml
   argocd app sync motiv-agent
   argocd app wait motiv-agent --sync --health --timeout 300
   ```

   Yangi Application mavjud Deployment, Service va HTTPRoute'ni shu nomlarda qabul
   qiladi; selector, Secret reference va image o'zgarmaydi.

5. Eski Application prune'ini qayta yoqishdan OLDIN ownership transferni majburiy
   tekshiring. Avval Argo tracking usulini ko'ring; config qiymati bo'sh bo'lsa live
   resursdagi annotation/labeldan qaysi biri ishlatilayotganini aniqlang:

   ```bash
   kubectl get configmap argocd-cm -n argocd \
     -o jsonpath='{.data.application\.resourceTrackingMethod}{"\n"}'
   argocd app get motiv-agent
   argocd app resources motiv-agent
   kubectl get deployment motiv-agent -n agent \
     -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/tracking-id}{" | "}{.metadata.labels.app\.kubernetes\.io/instance}{"\n"}'
   kubectl get service motiv-agent -n agent \
     -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/tracking-id}{" | "}{.metadata.labels.app\.kubernetes\.io/instance}{"\n"}'
   kubectl get httproute motiv-agent -n agent \
     -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/tracking-id}{" | "}{.metadata.labels.app\.kubernetes\.io/instance}{"\n"}'
   ```

   Annotation tracking'da uchala tracking ID `motiv-agent:` bilan boshlanishi kerak.
   Label tracking'da uchalasining `app.kubernetes.io/instance` qiymati `motiv-agent`
   bo'lishi kerak. Har ikki holatda yangi Application resource tree'ida uchala resurs
   ko'rinishi va unresolved shared-resource warning bo'lmasligi shart. Bu gate o'tmasa
   eski `agents` auto-sync/prune'ini yoqmang.

6. Motiv health va webhookni tekshiring:

   ```bash
   kubectl get deployment motiv-agent -n agent
   kubectl get pods -n agent -l app.kubernetes.io/name=motiv-agent
   kubectl get service,httproute -n agent motiv-agent
   kubectl logs deployment/motiv-agent -n agent --since=10m
   ```

7. Eski `agents` Application'ni yangi manifest bilan sync qiling va auto-sync'ni qayta yoqing.
   `argocd/agents.yaml` automated policy'ni qaytarishi sabab bu qadam faqat ownership
   gate o'tgach bajariladi:

   ```bash
   kubectl apply -f argocd/agents.yaml
   argocd app sync agents
   argocd app wait agents --sync --health --timeout 300
   ```

8. Yakuniy tekshiruv:

   ```bash
   kubectl get application agents motiv-agent -n argocd
   kubectl get deployment venu-agent lattaputta-agent motiv-agent -n agent
   ```

Ikkala Application `Synced/Healthy` bo'lishi, `motiv-agent` esa faqat yangi
Application resource tree'ida ko'rinishi kerak.

## Rollback

### Ownership transferdan oldin

Yangi Application render yoki sync qilmasa, eski `agents` Application hali pauzada
bo'ladi. Deploy commitni revert qilib, `argocd/agents.yaml` va `charts/agents`ga Motiv
resurslarini qaytaring, so'ng `agents`ni sync qilib auto-sync'ni qayta yoqing.

### Ownership transferdan keyin

Yangi `motiv-agent` uchala resursni qabul qilganidan keyin rollback kerak bo'lsa:

1. **Ikkala** Application auto-sync/prune'ini pauza qiling.
2. Eski `charts/agents` Motiv manifestlari va `motivValues` source'ini Git'da qaytaring.
   Restored `argocd/agents.yaml` support values source'ini ko'rsatishi va joriy immutable
   Motiv image tagini render qilishi shart.
3. Ikkala Application pauzada ekanini tekshirgach restored Application spec'ini live'ga
   apply qiling, so'ng `agents`ni sync qiling:

   ```bash
   kubectl apply -f argocd/agents.yaml
   argocd app sync agents
   argocd app wait agents --sync --health --timeout 300
   ```

   Apply automated policy'ni qayta yoqishi mumkin, shuning uchun oldingi ikki gate o'tmay
   turib uni bajarmang. Deployment, Service, HTTPRoute ownership'i yana `agents`ga
   o'tganini va Motiv healthy ekanini tekshiring.
4. Standalone Application'ni live resurslarni saqlagan holda non-cascading o'chiring:

   ```bash
   argocd app delete motiv-agent --cascade=false
   ```

5. Ownership va health tekshirilgach `agents` auto-sync/prune'ini qayta yoqing.

Standalone Application'ni cascading delete bilan o'chirmang. Har ikki rollbackda ham
PostgreSQL, PVC va Secretlarni o'chirmang.
