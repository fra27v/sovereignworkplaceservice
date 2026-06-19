# Initialize Global OpenBao

This runbook initializes Global OpenBao on the `vps-family-control` operator-plane VPS.

Run this only after Global OpenBao has been installed and the `openbao-global-0` pod is reachable, but before OpenBao has been initialized. The initialization step creates administrative recovery material and the initial root token.

## Preconditions

- Local OpenBao files have been prepared with `prepare-local-openbao-files.sh`.
- The Helm dry-run has been reviewed with `render-openbao-global.sh`.
- Global OpenBao has been installed with `install-openbao-global.sh`.
- `kubectl -n openbao-operator get pods,svc,pvc` shows the OpenBao pod and storage resources.
- OpenBao is not initialized yet.

## Run Initialization

Run the script on the `vps-family-control` operator-plane VPS:

```bash
cd /path/to/sovereignworkplaceservice
k8s/operator-plane/environments/vps-family-control/openbao/scripts/initialize-openbao-global.sh
```

The script checks `bao status -tls-skip-verify` first. It refuses to continue if OpenBao is already initialized and requires the status output to show `Initialized              false`.

The init JSON is saved locally at:

```text
${HOME}/openbao-bootstrap/openbao-global/openbao-global-init.json
```

The script creates the parent directory with mode `0700` and sets the init file mode to `0600`.

## Protect The Init File

The init file contains the initial root token and recovery material. It must never be committed, pasted into chat, attached to tickets, copied into runbooks, or printed in logs.

Losing the init file can lock out administration if no other administrative access has been established. Store it according to the operator-plane backup and custody procedure before continuing.

After initialization, do not regenerate the static seal key at:

```text
/var/lib/sovereignworkplaceservice/openbao/seal/unseal-20260618-1.key
```

Regenerating or replacing that key after OpenBao has data can prevent Global OpenBao from unsealing the existing storage.

## Next Step

The next runbook will enable audit logging and configure transit for downstream tenant OpenBao auto-unseal. Do not enable audit or transit from the initialization script.
