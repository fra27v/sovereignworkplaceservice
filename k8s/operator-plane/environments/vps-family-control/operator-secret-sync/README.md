# Operator Secret Sync

This directory contains the first one-shot Kubernetes Job for projecting operator-plane secrets from Global OpenBao KV into runtime Kubernetes Secrets.

OpenBao KV is the source of truth. Kubernetes Secrets are runtime projections. Local `.env` files are bootstrap, import, and recovery material only.

## Why A Job

The sync runs in Kubernetes so the workload can authenticate to OpenBao with Kubernetes auth and its mounted ServiceAccount token. This avoids storing static OpenBao tokens in Kubernetes Secrets.

The Job is one-shot rather than a CronJob because the first version is meant to be explicit and reviewable during bootstrap. A reconciler or scheduled sync can be added later after the trust and PKI model is complete.

## Authentication

The Job uses:

- Namespace: `operator-secret-sync`
- ServiceAccount: `operator-plane-secret-sync`
- OpenBao auth path: `kubernetes`
- OpenBao role: `operator-plane-secret-sync`
- OpenBao policy: `operator-plane-secret-sync`

The ServiceAccount is bound only to namespace-scoped Roles that can get, create, update, and patch Secrets in:

- `kube-system`
- `operator-artifacts`

The sync namespace manifest also ensures the `operator-artifacts` namespace exists because the `--all` bootstrap order configures secret sync before the operator-artifacts workload is installed. It has no access to unrelated namespaces and does not touch `trading`.

## Secret Projections

The sync script reads:

- `operator-kv/operator-plane/traefik/ovh-dns01`
- `operator-kv/operator-plane/operator-artifacts/family-infra-01`

It creates or updates:

- `kube-system/traefik-ovh-dns-credentials`
- `operator-artifacts/operator-artifacts-basicauth`

For `operator-artifacts`, the script derives the `users` htpasswd line inside the pod from `username` and `token`. The chosen implementation uses `openssl passwd -apr1 -stdin` because it avoids passing the token as a command-line argument and keeps the required image small. The generated htpasswd line is never echoed.

## Image Contract

The Job image is explicit: `operator-secret-sync:0.1.0`.

That image must provide:

- `/usr/local/bin/bash`
- `curl`
- `jq`
- `kubectl`
- `openssl`
- CA certificates

The image is intentionally a small local or private tool image contract for this sync Job. Do not add static OpenBao tokens to the image or to Kubernetes Secrets.

The sync logic is kept as a normal repository script at:

```text
scripts/sync-operator-plane-secrets.sh
```

The install script creates the runtime ConfigMap from that file with `kubectl create configmap --from-file ... --dry-run=client -o yaml | kubectl apply -f -`. This keeps the script easy to review and lint without requiring an image build for every sync logic change.

## OpenBao TLS

The Job defaults to:

```text
https://openbao-global.openbao-operator.svc:8200
```

It does not use insecure TLS skip verification by default.

The manifest includes a placeholder ConfigMap volume named `openbao-ca-bundle` mounted at:

```text
/var/run/openbao-ca/ca.crt
```

Until Operator PKI is implemented, the current bootstrap CA or certificate authority bundle must be projected into that ConfigMap by an explicit, safe procedure. Operator PKI will cleanly solve OpenBao CA bundle trust for in-cluster clients.

## Apply And Verify

Use:

```bash
./k8s/operator-plane/environments/vps-family-control/operator-secret-sync/scripts/install-operator-secret-sync.sh --dry-run
./k8s/operator-plane/environments/vps-family-control/operator-secret-sync/scripts/install-operator-secret-sync.sh
./k8s/operator-plane/environments/vps-family-control/operator-secret-sync/scripts/verify-operator-secret-sync.sh
```

The install script does not run destructive cleanup. It only deletes an old Job with the exact same name before reapplying the Job, because Kubernetes Job pod templates are immutable.
