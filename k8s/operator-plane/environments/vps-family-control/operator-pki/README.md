# VPS Family Control Operator PKI

This directory contains the environment-specific Operator PKI foundation for
`vps-family-control`.

Operator PKI uses the central environment entrypoint:

```text
k8s/operator-plane/environments/vps-family-control/operator-plane.env
```

Do not create `operator-pki.env` as an operational file. Copy
`operator-plane.env.example` to `operator-plane.env`, keep it out of Git, and
set permissions to `0600`. Public service hostnames and internal OpenBao DNS
names are derived from the central base domain, service name, namespace, and
cluster DNS suffix where possible.

Configure the Operator PKI foundation:

```bash
./k8s/operator-plane/environments/vps-family-control/operator-pki/scripts/configure-openbao-operator-pki.sh --dry-run
./k8s/operator-plane/environments/vps-family-control/operator-pki/scripts/configure-openbao-operator-pki.sh
```

Verify the foundation without changing OpenBao:

```bash
./k8s/operator-plane/environments/vps-family-control/operator-pki/scripts/verify-openbao-operator-pki.sh
```

This stage creates or verifies the OpenBao PKI mount, creates the internal
Operator CA only when missing, configures the `operator-vault` issuance role,
and exports only the public CA bundle. It does not issue or install the final
`operator-vault` runtime TLS certificate, does not rotate existing OpenBao TLS,
and does not expose `operator-vault`.
