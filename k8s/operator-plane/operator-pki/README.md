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

The environment uses a single operational env entrypoint:

```text
k8s/operator-plane/environments/vps-family-control/operator-plane.env
```

`operator-pki.env` is not an operational file. Operator PKI settings are in the
central `operator-plane.env.example` schema, and scripts derive service
hostnames and internal DNS names instead of requiring repeated full strings.

Runbooks live under:

```text
k8s/operator-plane/operator-pki/runbooks/
```

Operator PKI configure and verify are phases of the environment bootstrap and
verify orchestrators. This stage does not issue or install the final
`operator-vault` runtime TLS artifact, does not rotate existing OpenBao TLS,
and does not expose `operator-vault` through Traefik.
