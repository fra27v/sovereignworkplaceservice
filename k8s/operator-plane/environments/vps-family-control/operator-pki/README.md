# VPS Family Control Operator PKI

This directory contains the environment-specific Operator PKI foundation for
`vps-family-control`.

Copy `operator-pki.env.example` to `operator-pki.env`, keep the real file out
of Git, and set permissions to `0600`.

The real environment file must not contain private keys, certificates, tokens,
OpenBao init material, public IPs, real domains, or emails. It contains only
local paths and non-secret OpenBao PKI settings.

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
`operator-vault` runtime TLS certificate.
