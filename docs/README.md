# Lab Sovrano Documentation

This directory contains the repository documentation-as-code. The documentation describes only what exists in the repository and separates implemented items from future or target items.

Do not include secrets, tokens, `role_id`, `secret_id`, private keys, certificates, or generated sensitive values in these files.

## Index

- [Overview](overview.md)
- [Repository structure](repository-structure.md)
- [Traefik and networking](traefik-networking.md)
- [Vault and secrets](vault-secrets.md)
- [Identity flow: HR, midPoint, Keycloak](identity-flow.md)
- [Nextcloud and Collabora](nextcloud-collabora.md)
- [Service onboarding pattern](service-onboarding.md)
- [Operations runbooks](operations-runbooks.md)
- [Backup and restore baseline](backup-restore.md)
- [k3s migration plan](k3s-migration-plan.md)
- [OpenBao and Valkey migration notes](openbao-valkey-migration-notes.md)

## ADR

- [ADR 0001 - Documentation-as-code before the wiki](adr/0001-docs-as-code-before-wiki.md)
- [ADR 0002 - Docker first, k3s later](adr/0002-docker-first-k3s-later.md)
- [ADR 0003 - Vault to OpenBao target](adr/0003-vault-to-openbao-target.md)
- [ADR 0004 - Redis to Valkey target](adr/0004-redis-to-valkey-target.md)

## Runbook

- [Renew internal certificates](runbooks/renew-internal-certificates.md)
- [Restart services](runbooks/restart-services.md)
- [Unseal Vault](runbooks/unseal-vault.md)
- [Onboard a new service](runbooks/onboard-new-service.md)
- [Troubleshoot Traefik routing](runbooks/troubleshoot-traefik-routing.md)
- [Troubleshoot Vault Agent](runbooks/troubleshoot-vault-agent.md)
