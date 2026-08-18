# Traefik vps-family-control Environment

Environment-specific Traefik material for `vps-family-control` belongs here.

This area contains placeholders and runbooks for DNS-01 ACME integration. Do not commit real domains, emails, OVH credentials, certificates, keys, or tokens.

`operator-artifacts.<domain>` uses HTTP routing with Let's Encrypt DNS-01.
`operator-vault.<domain>` uses Traefik TCP passthrough instead: an
`IngressRouteTCP` on `websecure` routes `HostSNI` to `openbao-global:8200`, and
a MiddlewareTCP `ipAllowList` restricts source IP ranges. OpenBao terminates TLS
with the Operator CA-issued certificate; clients verify it with
`operator-ca-bundle.pem`.
