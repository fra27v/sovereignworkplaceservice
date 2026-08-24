# family-infra status

Date: 2026-08-24

## Summary

- k3s baseline verified with pinned version `v1.36.1+k3s1`
- packaged Traefik verified
- ServiceLB verified
- whoami routing verified with the packaged `traefik` IngressClass
- regression suite verified

## k3s baseline

Status: installed and verified

Verified:
- node Ready
- kube-system pods healthy
- secrets encryption enabled
- kubeconfig mode 0600
- key ports checked
- verify packaged Traefik HelmChart, Deployment, and LoadBalancer Service
- verify ServiceLB daemonset and pod readiness for Traefik
- verify Traefik Service ports `80/TCP` and `443/TCP`

## Packaged Traefik

Status: installed and verified

Verified:
- namespace: kube-system
- HelmChart: traefik
- Deployment: traefik
- Service: traefik
- Service type: LoadBalancer
- Service ports: 80/TCP and 443/TCP
- IngressClass: traefik
- ServiceLB daemonset name prefix: svclb-traefik-

## Smoke test

Status: verified

Verified:
- namespace: smoke-whoami
- host: whoami.internal
- ingress class: traefik
- response includes Hostname and Traefik forwarded headers

## Regression suite

Status: passed

Verified:
- k3s baseline verification
- whoami routing smoke test apply
- whoami routing smoke test verification
