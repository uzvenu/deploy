# CRM host TLS proxy

`nginx/crm.venu.uz.conf` is the CRM-only host vhost on `195.26.230.199`.
The host terminates TLS and forwards Host `crm.venu.uz` to the existing Gateway
NodePort `127.0.0.1:30025`. Kubernetes workloads/routes remain GitOps-managed.

The dedicated Let's Encrypt certificate is under
`/etc/letsencrypt/live/crm.venu.uz/`; private keys never belong in this repository.
Webroot validation uses `/var/www/crm-acme`. Certbot renewal is scheduled; the
host deploy hook `crm-nginx-reload` tests nginx before its graceful reload.

On 2026-10-06 the CRM-only vhost passed `nginx -t`, the certificate was issued,
HTTPS hostname verification passed, and HTTP redirected to HTTPS. The upstream
still returned 404 because the CRM workload/HTTPRoute was not active at that time.
This is TLS verification, not proof of CRM runtime readiness.

Host vhosts are outside Kubernetes. Review and test changes before installing;
never overwrite the existing multi-brand vhost. Keep an isolated CRM vhost backup.
