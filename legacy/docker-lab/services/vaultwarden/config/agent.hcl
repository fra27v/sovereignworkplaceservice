pid_file = "/tmp/pidfile"

auto_auth {
  method "approle" {
    mount_path = "auth/approle"

    config = {
      role_id_file_path = "/config/role_id"
      secret_id_file_path = "/config/secret_id"
      remove_secret_id_file_after_reading = false
    }
  }

  sink "file" {
    config = {
      path = "/tmp/token"
    }
  }
}

vault {
  address = "http://vault:8200"
}

template {
  source = "/templates/vaultwarden.env.tpl"
  destination = "/secrets/vaultwarden.env"
  perms = "0640"
}
