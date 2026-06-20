# Read-only policy for the in-cluster operator-plane secret sync Job.
#
# This policy intentionally allows only the exact KV v2 data paths required by
# the sync Job, plus minimal metadata read/list access for existence checks.
# It does not allow create, update, delete, destroy, transit, pki, sys, auth,
# audit, or unrelated KV paths.

path "operator-kv/data/operator-plane/traefik/ovh-dns01" {
  capabilities = ["read"]
}

path "operator-kv/data/operator-plane/operator-artifacts/family-infra-01" {
  capabilities = ["read"]
}

path "operator-kv/data/operator-plane/operator-artifacts/family-infra-01-config" {
  capabilities = ["read"]
}

path "operator-kv/metadata/operator-plane/*" {
  capabilities = ["read", "list"]
}
