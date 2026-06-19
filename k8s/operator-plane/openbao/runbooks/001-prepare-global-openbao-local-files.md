# Prepare Global OpenBao Local Files

This runbook prepares local filesystem material for Global OpenBao on the `vps-family-control` operator-plane VPS.

These files stay outside Git because they include secret or private material used to start and protect Global OpenBao. Do not commit generated keys, TLS private keys, certificates created for a specific host, root tokens, recovery keys, unseal keys, kubeconfigs, passwords, or private keys.

## Security Model

The static seal key used here is a family/demo compromise. It keeps the lab operable with a small operational footprint, but it is weaker than a production-grade external KMS, HSM, or manually controlled unseal process.

Compromise of VPS root compromises the Global OpenBao unseal path because root can read or replace local files under `/var/lib/sovereignworkplaceservice/openbao/`. Treat root access to the operator-plane VPS as equivalent to control over Global OpenBao startup.

The OpenBao Helm chart runs the pod as a non-root user with group ID `1000`. The static seal key and TLS private key are mounted from read-only hostPath volumes, so they must be group-readable by that pod group. This is why the local secret files use `root:1000` ownership and mode `0440` instead of `root:root` mode `0400`. This access model is acceptable only for the family/demo static-seal compromise documented here.

## Prepare Files

Run the script on the `vps-family-control` operator-plane VPS:

```bash
cd /path/to/sovereignworkplaceservice
sudo k8s/operator-plane/environments/vps-family-control/openbao/scripts/prepare-local-openbao-files.sh
```

The script is idempotent. It creates the directory layout if needed, creates the static seal key only when missing, and creates the local self-signed TLS key and certificate only when both TLS files are missing.

Expected local paths:

```text
/var/lib/sovereignworkplaceservice/openbao/seal/unseal-20260618-1.key
/var/lib/sovereignworkplaceservice/openbao/tls/tls.key
/var/lib/sovereignworkplaceservice/openbao/tls/tls.crt
/var/lib/sovereignworkplaceservice/openbao/audit/
```

## Verify Permissions

Verify metadata only. Do not print file contents.

```bash
sudo stat -c '%U:%G %a %n' \
  /var/lib/sovereignworkplaceservice/openbao/seal \
  /var/lib/sovereignworkplaceservice/openbao/seal/unseal-20260618-1.key \
  /var/lib/sovereignworkplaceservice/openbao/tls \
  /var/lib/sovereignworkplaceservice/openbao/tls/tls.key \
  /var/lib/sovereignworkplaceservice/openbao/tls/tls.crt \
  /var/lib/sovereignworkplaceservice/openbao/audit
```

Expected permissions:

```text
root:1000 750 /var/lib/sovereignworkplaceservice/openbao/seal
root:1000 440 /var/lib/sovereignworkplaceservice/openbao/seal/unseal-20260618-1.key
root:1000 750 /var/lib/sovereignworkplaceservice/openbao/tls
root:1000 440 /var/lib/sovereignworkplaceservice/openbao/tls/tls.key
root:root 444 /var/lib/sovereignworkplaceservice/openbao/tls/tls.crt
root:root 750 /var/lib/sovereignworkplaceservice/openbao/audit
```

Verify the static seal key size without printing it:

```bash
sudo stat -c '%s %n' /var/lib/sovereignworkplaceservice/openbao/seal/unseal-20260618-1.key
```

The size must be `32` bytes.

Verify the certificate is parseable without printing private key material:

```bash
openssl x509 \
  -in /var/lib/sovereignworkplaceservice/openbao/tls/tls.crt \
  -noout -subject -issuer -dates
```

## Do Not Share

Do not paste these into chat, tickets, logs, pull requests, commits, or runbook notes:

- Static seal key contents.
- TLS private key contents.
- OpenBao root tokens.
- Recovery keys or unseal keys.
- Kubernetes kubeconfigs.
- Passwords or private keys.
- Any generated local file under `/var/lib/sovereignworkplaceservice/openbao/` that is not explicitly sanitized.
