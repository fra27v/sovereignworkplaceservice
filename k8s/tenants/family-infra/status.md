# family-infra status

Date: 2026-06-18

## Summary

- k3s baseline OK
- Traefik runtime OK
- whoami routing OK
- regression suite OK

## k3s baseline

Status: installed and verified

Verified:
- node Ready
- kube-system pods healthy
- embedded k3s Traefik absent
- secrets encryption enabled
- kubeconfig mode 0600
- key ports checked

## Runtime Traefik

Status: installed and verified
Release: traefik-family-infra
Namespace: ingress-family-infra
IngressClass: traefik-family-infra

Verified:
- Traefik pod Running
- Traefik deployment successfully rolled out
- no LoadBalancer Service created
- HTTP route reachable through hostPort 80
- HTTPS endpoint reachable through hostPort 443
- whoami routing smoke test passed

Smoke test:
- namespace: smoke-whoami
- host: whoami.internal
- ingress class: traefik-family-infra
- response includes Hostname and Traefik forwarded headers

## Regression suite

Status: passed

Verified:
- k3s baseline verification
- runtime Traefik verification
- whoami routing smoke test apply
- whoami routing smoke test verification
