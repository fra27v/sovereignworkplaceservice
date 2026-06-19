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

## Execution Order

1. Copy env examples to real env files:

   ```bash
   cp k8s/operator-plane/environments/vps-family-control/traefik/traefik-acme-dns01.env.example \
     k8s/operator-plane/environments/vps-family-control/traefik/traefik-acme-dns01.env
   cp k8s/operator-plane/environments/vps-family-control/traefik/traefik-ovh-credentials.env.example \
     k8s/operator-plane/environments/vps-family-control/traefik/traefik-ovh-credentials.env
   ```

2. Edit the ACME email and OVH credentials in the real env files.

3. Use Let's Encrypt staging first by setting `TRAEFIK_ACME_CA_SERVER` to the staging URL in the local ACME env file.

4. Create the OVH Kubernetes Secret:

   ```bash
   k8s/operator-plane/environments/vps-family-control/traefik/scripts/create-traefik-ovh-dns-secret.sh
   ```

5. Render the HelmChartConfig:

   ```bash
   k8s/operator-plane/environments/vps-family-control/traefik/scripts/render-traefik-acme-dns01-ovh.sh
   ```

6. Install the HelmChartConfig for k3s reconciliation:

   ```bash
   sudo k8s/operator-plane/environments/vps-family-control/traefik/scripts/install-traefik-acme-dns01-ovh.sh
   ```

7. Verify Traefik:

   ```bash
   k8s/operator-plane/environments/vps-family-control/traefik/scripts/verify-traefik-acme-dns01-ovh.sh
   ```

8. After staging is verified, switch from staging to production by setting `TRAEFIK_ACME_CA_SERVER` to an empty value in the local ACME env file, then render and install again.

Do not paste OVH credentials into chat, tickets, logs, or Git.

Do not paste Secret YAML with `data` values.

ACME storage must not be deleted casually because it contains certificate account and issuance state.

## Scope

This step does not deploy `operator-artifacts`.

This step does not create OVH credentials.

This step does not create Kubernetes Secrets.

This step does not modify the running Traefik deployment.
