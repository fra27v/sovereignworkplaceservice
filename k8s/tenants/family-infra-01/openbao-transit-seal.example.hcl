# Example OpenBao transit seal configuration only.
# Replace values from environment-specific configuration before use.
# Do not commit real secrets.
# The seal key file must never be committed.
# The transit token must never be committed.
# Apps use Tenant OpenBao, not Global OpenBao.
# The Global OpenBao transit address must come from environment config.

seal "transit" {
  address         = "GLOBAL_OPENBAO_TRANSIT_ADDRESS_FROM_ENV_CONFIG"
  mount_path      = "GLOBAL_OPENBAO_TRANSIT_MOUNT_PATH_FROM_ENV_CONFIG"
  key_name        = "GLOBAL_OPENBAO_TRANSIT_KEY_NAME_FROM_ENV_CONFIG"
  tls_skip_verify = "false"
}
