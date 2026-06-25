# Operator PKI

Operator PKI is the OpenBao-managed certificate authority foundation for the
operator plane.

The first implementation creates a single internal Operator CA in Global
OpenBao for `vps-family-control`. The CA private key remains inside OpenBao.
Only the public CA bundle is exported for trust distribution.

Environment-specific scripts and examples live under:

```text
k8s/operator-plane/environments/vps-family-control/operator-pki/
```

Runbooks live under:

```text
k8s/operator-plane/operator-pki/runbooks/
```

This stage does not issue or install the final `operator-vault` runtime TLS
artifact and does not expose `operator-vault` through Traefik.
