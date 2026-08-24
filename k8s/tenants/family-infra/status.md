# family-infra status

Date: 2026-08-24

## Summary

- k3s baseline previously verified with pinned version `v1.36.1+k3s1`
- packaged Traefik and ServiceLB pending after the next config apply and k3s restart
- whoami routing pending re-verification with the packaged `traefik` IngressClass
- regression suite pending re-run

## k3s baseline

Status: installed and previously verified

Verified before this Git change:
- node Ready
- kube-system pods healthy
- secrets encryption enabled
- kubeconfig mode 0600
- key ports checked

Pending after this Git change:
- apply the updated common k3s config
- restart k3s
- verify packaged Traefik HelmChart, Deployment, and LoadBalancer Service
- verify ServiceLB daemonset and pod readiness for Traefik
- verify Traefik Service ports `80/TCP` and `443/TCP`

## Packaged Traefik

Status: pending reconciliation and verification

Expected:
- namespace: kube-system
- HelmChart: traefik
- Deployment: traefik
- Service: traefik
- Service type: LoadBalancer
- Service ports: 80/TCP and 443/TCP
- IngressClass: traefik
- ServiceLB daemonset name prefix: svclb-traefik-

## Smoke test

Status: pending re-verification

Expected:
- namespace: smoke-whoami
- host: whoami.internal
- ingress class: traefik
- response includes Hostname and Traefik forwarded headers

## Regression suite

Status: pending re-run

Expected checks:
- k3s baseline verification
- whoami routing smoke test apply
- whoami routing smoke test verification
