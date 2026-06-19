# Configure Global OpenBao Transit For family-infra-01

This runbook configures Global OpenBao transit auto-unseal material for tenant `family-infra-01` on the `vps-family-control` operator-plane VPS.

This does not install Tenant OpenBao.

## Purpose

Global OpenBao transit is required before Tenant OpenBao can use `seal "transit"`. The Global OpenBao transit key encrypts and decrypts Tenant OpenBao seal material during tenant startup.

Applications must not use Global OpenBao directly. Applications will use Tenant OpenBao. The token created by this procedure is for Tenant OpenBao auto-unseal only, not for applications.

## Preconditions

Global OpenBao must be initialized, unsealed, and reachable before running this procedure.

File audit logging must already be enabled and verified before creating transit keys or issuing transit tokens.

Critical material custody must already be complete for:

```text
~/openbao-bootstrap/openbao-global/openbao-global-init.json
/var/lib/sovereignworkplaceservice/openbao/seal/unseal-20260618-1.key
```

## What The Script Creates

The script creates or verifies:

- The `transit/` secrets engine.
- The `family-infra-01-autounseal` transit key.
- The `family-infra-01-transit-autounseal` policy with only encrypt/decrypt update capabilities for that key.
- An orphan periodic tenant token with that policy.

The tenant token JSON is written to:

```text
~/openbao-bootstrap/openbao-global/family-infra-01-transit-token.json
```

This token file is critical material. Save it in a secure location outside Git. Do not paste it into chat, tickets, logs, pull requests, or runbooks.

## Run The Script

Run on the `vps-family-control` operator-plane VPS:

```bash
cd /path/to/sovereignworkplaceservice
k8s/operator-plane/environments/vps-family-control/openbao/scripts/configure-openbao-global-transit-family-infra-01.sh
```

The script reads the Global OpenBao root token from the init JSON without printing it. It writes the tenant token JSON directly to the token file and sets mode `0600`.

The script also performs a safe transit smoke test using a harmless test value. It does not print the root token, tenant token, ciphertext, plaintext, or init JSON contents.

Safe successful output should state that:

- Global OpenBao is initialized and unsealed.
- File audit is enabled.
- The transit engine is enabled.
- The transit key exists.
- The minimal tenant policy was written.
- The tenant token JSON was written to the local bootstrap path.
- The transit smoke test passed.

## Handling The Tenant Token

The tenant token is for Tenant OpenBao auto-unseal only. It is not an application token and must not be given to applications.

Store the token file securely outside Git before using it to configure Tenant OpenBao.

Do not retire the Global OpenBao init JSON until audit, transit, tenant auto-unseal policy, and tenant token creation have all been completed and verified.

## Backup And DR

Backup and disaster recovery will be handled later after both Global OpenBao and Tenant OpenBao are installed and validated.

This runbook does not define the full backup or restore procedure.
