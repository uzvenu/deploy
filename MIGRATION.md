# Raw Kustomize manifestlardan Helm multi-source modeliga o'tish

Bu cutover resource nomlari, namespace'lar, selectorlar, PVC va Secret reference'larini
o'zgartirmaydi. Faqat Argo CD render manbasi Kustomize'dan Helm multi-source'ga o'tadi.

## Old shartlar

1. Ushbu repo `uzvenu/deploy` private reposining `master` branchiga push qilingan bo'lsin.
2. `uzvenu/backend`da `helm/values.yaml`, `uzvenu/chatbot`da `helm/values.yaml` push qilingan bo'lsin.
3. Argo CD uchala private reponi o'qiy olsin.
4. Chartlar lint va template tekshiruvdan o'tsin.

## Cutover

```bash
kubectl config current-context
kubectl cluster-info
kubectl auth can-i patch applications.argoproj.io -n argocd
kubectl apply -f argocd/venu.yaml -f argocd/agents.yaml
kubectl get applications.argoproj.io venu agents -n argocd
```

Ikkalasi `Synced` va `Healthy` bo'lgach, workloadlarni tekshiring:

```bash
kubectl get deployment -n venu
kubectl get deployment -n agent
kubectl rollout status deployment/venu-api -n venu
kubectl rollout status deployment/venu-worker -n venu
kubectl rollout status deployment/venu-agent -n agent
kubectl rollout status deployment/lattaputta-agent -n agent
```

## Rollback

Backend raw manifestlari hali `master`da mavjud paytda eski source'lar:

- `venu`: `https://github.com/uzvenu/backend.git`, path `deploy/k8s`, revision `master`
- `agents`: `https://github.com/uzvenu/backend.git`, path `deploy/agents`, revision `master`

Backenddan eski `deploy/` katalogini faqat Helm cutover muvaffaqiyatli bo'lgandan keyin
push qiling.
