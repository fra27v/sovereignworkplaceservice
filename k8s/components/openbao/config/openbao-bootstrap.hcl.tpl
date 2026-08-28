ui = false
disable_mlock = true

listener "tcp" {
  address     = "127.0.0.1:8200"
  tls_disable = true
}

storage "raft" {
  path    = "/openbao/data"
  node_id = "${TENANT_NODE}"
}

seal "transit" {
  address         = "${TRANSIT_ADDRESS}"
  key_name        = "${TRANSIT_KEY_NAME}"
  mount_path      = "${TRANSIT_MOUNT_PATH}"
  tls_ca_cert     = "${TRANSIT_CA_BUNDLE_PATH}"
  tls_server_name = "${TRANSIT_TLS_SERVER_NAME}"
}

audit "file" "stdout" {
  description = "Tenant OpenBao stdout audit device"
  options = {
    file_path = "stdout"
    log_raw   = "false"
  }
}

telemetry {
  disable_hostname = true
}
