# Traefik Manifests

Environment-specific Traefik manifests for `vps-family-control` belong here.

Commit sanitized manifests and templates only. Do not commit real credentials, certificates, keys, or domains.

Current templates:

- `traefik-helmchartconfig-acme-dns01-ovh.yaml.tpl`: k3s HelmChartConfig template for Traefik Let's Encrypt DNS-01 with OVH credentials delivered through a Kubernetes Secret.
