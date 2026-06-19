# Retire Global OpenBao Bootstrap Material

This runbook retires the local Global OpenBao init JSON from the `vps-family-control` operator-plane VPS after bootstrap is complete.

This is not the full backup or restore procedure. Full backup and disaster recovery will be standardized after both Global OpenBao and Tenant OpenBao are installed and validated.

## When To Run

Run this only after Global OpenBao bootstrap is complete.

Do not run this before all of the following have been created and verified:

- File audit logging.
- Transit engine.
- Tenant auto-unseal policy.
- Tenant transit token.

The init JSON contains the initial root token and recovery material. It must be saved in a secure external location before local deletion.

## Material Boundaries

The script targets only:

```text
~/openbao-bootstrap/openbao-global/openbao-global-init.json
```

The script must not touch:

```text
/var/lib/sovereignworkplaceservice/openbao/seal/unseal-20260618-1.key
/var/lib/sovereignworkplaceservice/openbao/tls/tls.key
/var/lib/sovereignworkplaceservice/openbao/tls/tls.crt
```

Recovery keys do not replace the static seal key. The static seal key must remain on the VPS for runtime auto-unseal and must also be backed up securely for disaster recovery.

## Retire The Local Copy

Run on the `vps-family-control` operator-plane VPS:

```bash
cd /path/to/sovereignworkplaceservice
k8s/operator-plane/environments/vps-family-control/openbao/scripts/retire-openbao-global-bootstrap-material.sh
```

The script prints safe metadata for the local init JSON, requires an exact confirmation phrase, deletes only that file, and verifies it no longer exists.

The required confirmation phrase is:

```text
I HAVE SECURED GLOBAL OPENBAO INIT MATERIAL
```

Do not paste the init JSON contents into chat, tickets, logs, pull requests, or runbooks.

## Important Limits

This step removes a local bootstrap copy only. It does not prove that backup custody is complete, and it does not test restore.

Secure deletion is not guaranteed on SSDs, copy-on-write filesystems, or cloud volumes. The real controls are secure custody, encrypted storage, and deleting unnecessary local copies.

The static seal key must not be regenerated after initialization. Replacing it can prevent Global OpenBao from unsealing existing encrypted storage.
