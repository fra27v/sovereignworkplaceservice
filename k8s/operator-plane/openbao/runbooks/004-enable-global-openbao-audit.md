# Enable Global OpenBao Audit

This runbook documents declarative file audit logging for Global OpenBao on the `vps-family-control` operator-plane VPS.

Audit logging must be enabled before creating transit keys or issuing transit tokens. The audit log gives operators a record of bootstrap actions that affect downstream tenant OpenBao auto-unseal.

Current OpenBao requires declarative, config-based audit device management. API-based `bao audit enable` is intentionally not used.

## Security Notes

Audit logs are sensitive. They may contain request paths, identities, client metadata, and other operational context. Treat audit logs as protected operator-plane material.

The file audit device writes to:

```text
/openbao/audit/audit.log
```

The `/openbao/audit` directory is backed by the Global OpenBao audit PVC configured in the Helm values. Log rotation and retention will be standardized later in the backup and disaster recovery phase.

Audit is enabled by the Helm values in `k8s/operator-plane/environments/vps-family-control/openbao/values/openbao-global.values.yaml` and applied with `helm upgrade` through the Global OpenBao install script.

## Apply The Configuration

Render and review the Helm manifest first:

```bash
cd /path/to/sovereignworkplaceservice
k8s/operator-plane/environments/vps-family-control/openbao/scripts/render-openbao-global.sh
```

Then apply the values with the install script:

```bash
k8s/operator-plane/environments/vps-family-control/openbao/scripts/install-openbao-global.sh
```

The script performs a Helm upgrade. It does not initialize OpenBao and does not print secrets.

## Restart For OnDelete StatefulSet Updates

The OpenBao StatefulSet uses `updateStrategy: OnDelete`, so `kubectl rollout status` is not valid for this release. Helm config changes may require deleting the pod manually so Kubernetes recreates it from the updated StatefulSet template.

After OpenBao is initialized and auto-unseal has been verified, deleting `openbao-global-0` is safe because the PVCs persist and the static seal is configured.

Use this restart and wait pattern after applying Helm config changes:

```bash
kubectl -n openbao-operator delete pod openbao-global-0
kubectl -n openbao-operator wait --for=condition=Ready pod/openbao-global-0 --timeout=180s
kubectl -n openbao-operator exec openbao-global-0 -- bao status -tls-skip-verify
```

Always verify `bao status -tls-skip-verify` after restart before continuing.

## Verify Audit Is Enabled

After the upgraded pod is running and unsealed, verify audit registration:

```bash
k8s/operator-plane/environments/vps-family-control/openbao/scripts/verify-openbao-global-audit.sh
```

The verification script reads the root token from:

```text
~/openbao-bootstrap/openbao-global/openbao-global-init.json
```

It passes the token to the in-pod `bao audit list` command without printing it. A successful result includes:

```text
file/
```

The verified audit success state is:

- `bao audit list` shows `file/`.
- `/openbao/audit/audit.log` exists.

The verification script checks both conditions. It does not print or inspect audit log contents.

Do not inspect audit log contents as part of this runbook. Audit log contents must not be printed, pasted into chat, attached to tickets, or committed to Git.

## Troubleshooting

If audit commands fail with `x509: certificate signed by unknown authority`, ensure the script sets `VAULT_CACERT=/openbao/tls/tls.crt` inside the pod for authenticated `bao` commands.

If `bao audit list` does not show `file/`, confirm the rendered StatefulSet contains the declarative `audit "file" "file"` stanza and that the running pod has been restarted from the updated Helm values.
