# Repository Structure

## Main Directories

- `core/traefik/`: Traefik reverse proxy, static configuration, and dynamic routes.
- `core/vault/`: HashiCorp Vault in Docker Compose, HCL configuration, and local file storage.
- `services/`: application services and identity components.
- `scripts/`: operational PowerShell scripts.
- `pki/`: internal CA, issued certificates, and sensitive or generated local files.
- `docs/`: documentation-as-code.

## Existing Services

- `services/keycloak/`: Keycloak, PostgreSQL, and Vault Agent.
- `services/identity/`: midPoint, PostgreSQL, Vault Agent, OrangeHRM sync, family-lab examples.
- `services/orangehrm/`: OrangeHRM, MariaDB, and Vault Agent.
- `services/nextcloud/`: Nextcloud, PostgreSQL, Redis, and Vault Agent.
- `services/collabora/`: Collabora Online and Vault Agent.
- `services/vaultwarden/`: Vaultwarden and Vault Agent.

## Recurring Service Pattern

Each service generally uses:

- `docker-compose.yml` for containers and volumes.
- `config/agent.hcl` for Vault Agent, when the service uses Vault secrets.
- `templates/` for Vault Agent templates.
- `secrets/` as the runtime destination for templates.
- `data/`, `var/`, `generated/`, or Docker volumes for persistent or generated data.

Do not document actual contents of `secrets/`, `data/`, `generated/`, `pki/issued/`, or files containing keys/tokens.

## Important Operational Files

- `core/traefik/traefik.yml`: entrypoints, dashboard, logging, and file provider.
- `core/traefik/dynamic/*.yml`: routes, TLS transports, and certificates.
- `core/vault/config/vault.hcl`: Vault listener, file storage, and API addresses.
- `scripts/new-service.ps1`: service onboarding by combining certificate and route creation.
- `scripts/issue-cert-if-missing.ps1`: certificate issuance from Vault PKI.
- `scripts/register-service.ps1`: Traefik route creation/update.
- `scripts/renew-traefik-certs.ps1`: certificate renewal for `*.internal.yml` routes.
- `scripts/unseal-vault.ps1`: local unseal using a key file.

TODO: formally distinguish versioned files from generated files, because the local repository also contains excluded or sensitive material.
