# Enable Traefik Let's Encrypt DNS-01 With OVH

This runbook documents the initial Traefik DNS-01 OVH skeleton for the `vps-family-control` operator-plane environment.

`operator-artifacts.<domain>` will use Let's Encrypt DNS-01 because it is an HTTPS artifact delivery endpoint.

`operator-vault.<domain>` will not use Let's Encrypt. The operator vault endpoint remains private Operator PKI with TLS terminated by OpenBao.

## Credential Model

DNS-01 uses OVH API credentials.

Real OVH credentials are stored in this gitignored local file:

```text
k8s/operator-plane/environments/vps-family-control/traefik/traefik-ovh-credentials.env
```

Use the example as a template:

```text
k8s/operator-plane/environments/vps-family-control/traefik/traefik-ovh-credentials.env.example
```

Do not commit real OVH credentials, tokens, certificates, keys, domains, emails, or IP addresses.

## Runtime Delivery

A Kubernetes Secret may be used to deliver OVH credentials to Traefik at runtime.

The Kubernetes Secret is runtime delivery, not the Git source of truth. The source material remains local, gitignored operator-plane material.

## ACME Settings

ACME DNS-01 settings are represented by:

```text
k8s/operator-plane/environments/vps-family-control/traefik/traefik-acme-dns01.env.example
```

Copy it to a local gitignored env file before use and replace placeholders.

`TRAEFIK_ACME_CA_SERVER=""` means Let's Encrypt production. `TRAEFIK_ACME_CA_SERVER` is only an optional diagnostic override for unusual troubleshooting.

Production ACME has rate limits, so reruns should be done carefully. Do not repeatedly delete ACME storage or force certificate reissuance during normal troubleshooting.

## Real Client Source IPs

The Traefik Service must preserve real client source IPs so Traefik
`IPAllowList` middleware can evaluate the operator home public IP correctly.

Set this in the real ACME DNS-01 env file:

```bash
TRAEFIK_SERVICE_EXTERNAL_TRAFFIC_POLICY="Local"
```

`Local` is required for `operator-artifacts` IPAllowList behavior. If the live
Service remains `externalTrafficPolicy=Cluster`, Traefik may see an internal
cluster source IP instead of the real client source IP, and allowlist decisions
can fail.

This repository manages the setting through k3s `HelmChartConfig`; do not patch
the live Traefik Service directly.

Safe verification:

```bash
kubectl -n kube-system get svc traefik -o jsonpath='{.spec.type}{" externalTrafficPolicy="}{.spec.externalTrafficPolicy}{"\n"}'
```

## Execution Order

1. Copy env examples to real env files:

   ```bash
   cp k8s/operator-plane/environments/vps-family-control/traefik/traefik-acme-dns01.env.example \
     k8s/operator-plane/environments/vps-family-control/traefik/traefik-acme-dns01.env
   cp k8s/operator-plane/environments/vps-family-control/traefik/traefik-ovh-credentials.env.example \
     k8s/operator-plane/environments/vps-family-control/traefik/traefik-ovh-credentials.env
   ```

2. Edit the ACME email and OVH credentials in the real env files.

3. Create the OVH Kubernetes Secret:

   ```bash
   k8s/operator-plane/environments/vps-family-control/traefik/scripts/create-traefik-ovh-dns-secret.sh
   ```

4. Render the HelmChartConfig:

   ```bash
   k8s/operator-plane/environments/vps-family-control/traefik/scripts/render-traefik-acme-dns01-ovh.sh
   ```

5. Install the HelmChartConfig for k3s reconciliation:

   ```bash
   sudo k8s/operator-plane/environments/vps-family-control/traefik/scripts/install-traefik-acme-dns01-ovh.sh
   ```

6. Verify Traefik:

   ```bash
   k8s/operator-plane/environments/vps-family-control/traefik/scripts/verify-traefik-acme-dns01-ovh.sh
   ```

Do not paste OVH credentials into chat, tickets, logs, or Git.

Do not paste Secret YAML with `data` values.

ACME storage must not be deleted casually because it contains certificate account and issuance state.

## Secret data and temporary files

Never print Kubernetes Secret `.data` or full Secret YAML.

Kubernetes Secret values are base64-encoded, not encrypted for display.

If Secret data was printed or pasted, rotate the OVH credentials immediately.

Temporary rendered files under `/tmp` must be cleaned after render or install. The render script removes temporary output by default; use `--keep-output` only for explicit local inspection.

Do not paste OVH credentials or Secret contents into chat, logs, tickets, or Git.

## Scope

This step does not deploy `operator-artifacts`.

This step does not create OVH credentials.

This step does not create Kubernetes Secrets.

This step does not modify the running Traefik deployment.
