# Bootstrap import policy for operator-plane secrets.
#
# Actual bootstrap import can also be run with a root/admin identity during the
# first controlled setup. This policy is for a future limited importer identity.
#
# The policy allows create/update/read on the exact KV v2 data paths required
# for operator-plane secret import and minimal metadata read/list access. It
# intentionally does not allow delete, destroy, transit, pki, sys, auth, audit,
# or unrelated KV paths.

path "operator-kv/data/operator-plane/traefik/ovh-dns01" {
  capabilities = ["create", "update", "read"]
}

path "operator-kv/data/operator-plane/operator-artifacts/family-infra-01" {
  capabilities = ["create", "update", "read"]
}

path "operator-kv/data/operator-plane/operator-artifacts/family-infra-01-config" {
  capabilities = ["create", "update", "read"]
}

path "operator-kv/metadata/operator-plane/*" {
  capabilities = ["read", "list"]
}
