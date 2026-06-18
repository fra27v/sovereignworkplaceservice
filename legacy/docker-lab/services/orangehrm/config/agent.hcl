pid_file = "/secrets/vault-agent.pid"

auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path   = "/config/role_id"
      secret_id_file_path = "/config/secret_id"
      remove_secret_id_file_after_reading = false
    }
  }

  sink "file" {
    config = {
      path = "/secrets/.vault-token"
    }
  }
}

vault {
  address = "http://vault:8200"
}

template {
  source      = "/templates/db_root_password.ctmpl"
  destination = "/secrets/db_root_password"
}

