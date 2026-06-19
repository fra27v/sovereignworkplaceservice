# Global OpenBao Critical Material Custody

This runbook documents critical material custody for Global OpenBao on the `vps-family-control` operator-plane VPS.

Do not store this material in Git or Kubernetes Secrets. Do not paste it into chat, tickets, logs, pull requests, shell history, or runbook notes.

## Required Critical Material

The following material is required to retain administrative access and restore Global OpenBao encrypted storage:

```text
~/openbao-bootstrap/openbao-global/openbao-global-init.json
/var/lib/sovereignworkplaceservice/openbao/seal/unseal-20260618-1.key
```

The init JSON contains the initial root token and recovery material. It must be saved in a secure location outside Git and outside Kubernetes Secrets.

The static seal key is required to auto-unseal restored encrypted OpenBao storage. Recovery keys do not replace the static seal key. If the static seal key is missing or changed after data has been written, restored OpenBao storage may not be usable.

The static seal key must not be regenerated after initialization.

## Recommended Sensitive Material

The following TLS material should also be kept in secure custody:

```text
/var/lib/sovereignworkplaceservice/openbao/tls/tls.crt
/var/lib/sovereignworkplaceservice/openbao/tls/tls.key
```

The TLS private key is sensitive because it authenticates the local Global OpenBao endpoint. It does not decrypt OpenBao storage and does not replace the static seal key or init JSON.

## Versioned Reconstruction Material

The Git repository is versioned reconstruction material, especially:

```text
k8s/operator-plane/
```

The repository can reconstruct deployment intent, Helm values, scripts, policies, and runbooks. It must not contain the critical material listed above.

## Prohibited Handling

No critical material may be:

- Committed to Git.
- Stored in Kubernetes Secrets.
- Pasted into chat or tickets.
- Printed into logs.
- Left in shell history.
- Included in screenshots or copied into runbook notes.

Do not document actual token values, recovery key values, unseal key contents, TLS private key contents, or checksums of real secrets.

## Safe Verification

These commands list metadata only. They do not print secret contents.

```bash
ls -ld ~/openbao-bootstrap/openbao-global
ls -l ~/openbao-bootstrap/openbao-global/openbao-global-init.json
sudo stat -c '%U:%G %a %s %n' \
  /var/lib/sovereignworkplaceservice/openbao/seal/unseal-20260618-1.key \
  /var/lib/sovereignworkplaceservice/openbao/tls/tls.crt \
  /var/lib/sovereignworkplaceservice/openbao/tls/tls.key
```

Review only owner, group, mode, size, and path. Do not use `cat`, `less`, `head`, `tail`, `jq`, `openssl rsa`, or any command that prints secret values or private key material.

## Deferred Backup And Restore Testing

Backup and restore testing is intentionally deferred until both Global OpenBao and Tenant OpenBao are installed and the transit auto-unseal connection has been validated.

Do not add backup or restore automation until that deployment state exists and the test scope can cover both the Global OpenBao seal dependency and the tenant transit dependency.
