# Enable Global OpenBao Audit

This runbook enables file audit logging for Global OpenBao on the `vps-family-control` operator-plane VPS.

Audit logging must be enabled before creating transit keys or issuing transit tokens. The audit log gives operators a record of bootstrap actions that affect downstream tenant OpenBao auto-unseal.

## Security Notes

Audit logs are sensitive. They may contain request paths, identities, client metadata, and other operational context. Treat audit logs as protected operator-plane material.

The file audit device writes to:

```text
/openbao/audit/audit.log
```

The `/openbao/audit` directory is backed by the Global OpenBao audit PVC configured in the Helm values. Log rotation and retention will be standardized later in the backup and disaster recovery phase.

The initialization root token is used only for this bootstrap operation. Do not print it, paste it into chat, save it in shell history, or commit it to Git.

## Run The Script

Run this after Global OpenBao has been initialized and unsealed:

```bash
cd /path/to/sovereignworkplaceservice
k8s/operator-plane/environments/vps-family-control/openbao/scripts/enable-openbao-global-audit.sh
```

The script reads the root token from:

```text
~/openbao-bootstrap/openbao-global/openbao-global-init.json
```

It passes the token to the in-pod `bao` process without printing it. It does not enable transit.

## Verify Audit Is Enabled

The script prints `bao audit list` after enabling the file audit device. A successful result includes:

```text
file/
```

You can rerun the script safely. If `file/` is already enabled, it exits without changing the audit configuration.

Do not inspect audit log contents as part of this runbook. This runbook only enables the audit device and verifies that the device is registered.

## Troubleshooting

If audit commands fail with `x509: certificate signed by unknown authority`, ensure the script sets `VAULT_CACERT=/openbao/tls/tls.crt` inside the pod for authenticated `bao` commands.
