# Raw Kustomize manifestlardan Helm multi-source modeliga o'tish

Bu cutover resource nomlari, namespace'lar, selectorlar, PVC va Secret reference'larini
o'zgartirmaydi. Faqat Argo CD render manbasi Kustomize'dan Helm multi-source'ga o'tadi.

## Old shartlar

1. `uzvenu/backend`da `helm/values.yaml` push qilingan bo'lsin.
2. `uzvenu/chatbot` `main` branchida `helm/values.yaml` va same-repo tag bump qiladigan CD workflow push qilingan bo'lsin.
3. Argo CD private backend va chatbot values repolarini hamda public chart reposini o'qiy olsin.
4. Ushbu repo `uzvenu/deploy` `master` branchiga faqat values fayllari mavjudligi tekshirilgandan keyin push qilinsin.
5. `charts/venu`, `charts/agents` va `charts/motiv-agent` real application values bilan lint va template tekshiruvdan o'tsin.

## Cutover

Application'larni bir vaqtda ko'r-ko'rona apply qilmang. Avval har bir external values fayli target branchda borligini va Argo repository credential ishlashini tekshiring. Agent cutover tartibi qat'iy: chatbot values -> chatbot repo credential -> deploy Argo manifest.

```bash
kubectl config current-context
kubectl cluster-info
kubectl auth can-i patch applications.argoproj.io -n argocd
kubectl apply -f argocd/venu.yaml
kubectl get application venu -n argocd
kubectl apply -f argocd/agents.yaml
kubectl get application agents -n argocd
# Motiv split alohida kontrolli tartibda: MOTIV_SPLIT.md
kubectl get application motiv-agent -n argocd
```

Har bir Application alohida `Synced` va `Healthy` bo'lgach, workloadlarni tekshiring:

```bash
kubectl get deployment -n venu
kubectl get deployment -n agent
kubectl rollout status deployment/venu-api -n venu
kubectl rollout status deployment/venu-worker -n venu
kubectl rollout status deployment/venu-agent -n agent
kubectl rollout status deployment/lattaputta-agent -n agent
```

## Rollback

Eski raw `deploy/k8s` yoki `deploy/agents` pathlariga qaytmang — ular joriy source-of-truth emas.

Agent values source rollback'i kerak bo'lsa:

1. `uzvenu/chatbot/helm/values.yaml`dagi joriy immutable tagni oling.
2. `charts/agents/values.yaml`dagi tagni aynan shu qiymatga tenglashtirib `uzvenu/deploy`ga push qiling.
3. `argocd/agents.yaml`ni `charts/agents` single-source ko'rinishiga qaytaring.
4. Application manifestini yangilang va `Synced`/`Healthy` holatini tekshiring.

Tagni oldindan tenglashtirish chart defaultidagi eski image'ga kutilmagan rollbackni oldini oladi. Backend rollback'i ham shu tamoyilda: external values source olib tashlanishidan oldin joriy tag chart values'ga ko'chiriladi.
