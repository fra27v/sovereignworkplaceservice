# Traefik Scripts

Environment-specific Traefik helper scripts for `vps-family-control` belong here.

Scripts must not embed real OVH credentials, tokens, certificates, keys, emails, domains, or IP addresses.

Current scripts:

- `create-traefik-ovh-dns-secret.sh`: creates or updates the Traefik OVH DNS Kubernetes Secret from local gitignored env files without printing secret values.
- `render-traefik-acme-dns01-ovh.sh`: renders the k3s Traefik HelmChartConfig for Let's Encrypt DNS-01 OVH to `/tmp`.
- `install-traefik-acme-dns01-ovh.sh`: copies the rendered HelmChartConfig into the k3s server manifests directory for reconciliation.
- `verify-traefik-acme-dns01-ovh.sh`: verifies Secret metadata, HelmChartConfig, Traefik ACME DNS-01 arguments, Running pod state, and safe ACME-related logs.
