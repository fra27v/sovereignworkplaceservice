# OpenBao Policies

Policy definitions and examples for operator-plane OpenBao belong here.

Do not commit live credentials or tenant-specific secret values.

The `.hcl.example` files in this directory are Global OpenBao operator-plane examples. Real policy renderings that contain environment-specific secret material must stay local and outside Git.

Versioned policies:

- `family-infra-01-transit-autounseal.hcl`: minimal Global OpenBao transit encrypt/decrypt policy for the `family-infra-01-autounseal` key used by Tenant OpenBao auto-unseal.
