# family-infra Status

## k3s baseline

Status: installed and verified  
Date: 2026-06-18  
Node: family-infra  
Node IP: 192.168.1.34  
DNS: family-infra.internal  
k3s version: v1.35.5+k3s1  

Verified:
- node Ready
- CoreDNS Running
- local-path-provisioner Running
- metrics-server Running
- secrets encryption Enabled
- embedded Traefik absent
- ServiceLB disabled
- kubeconfig mode 0600
- only port 6443 listening before Traefik