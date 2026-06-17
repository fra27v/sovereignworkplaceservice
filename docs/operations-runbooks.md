# Operations Runbooks

This page is an operational index. Detailed runbooks are in `docs/runbooks/`.

## Available Runbooks

- [Renew internal certificates](runbooks/renew-internal-certificates.md)
- [Restart services](runbooks/restart-services.md)
- [Unseal Vault](runbooks/unseal-vault.md)
- [Onboard a new service](runbooks/onboard-new-service.md)
- [Troubleshoot Traefik routing](runbooks/troubleshoot-traefik-routing.md)
- [Troubleshoot Vault Agent](runbooks/troubleshoot-vault-agent.md)

## Operational Rules

- Do not copy secrets into tickets, shared logs, or documentation.
- Before restarting a service that depends on Vault, verify that Vault is unsealed.
- After Traefik route changes, check Traefik logs.
- After certificate renewal, restart Traefik if TLS files are already mounted but not reloaded.
- For services with databases, distinguish ephemeral containers from persistent volumes.

TODO: add a pre-flight checklist for maintenance windows.
