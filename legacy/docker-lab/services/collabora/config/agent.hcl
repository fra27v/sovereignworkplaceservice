vault {
  address = "http://vault:8200"
}

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

template {
  source      = "/templates/tls.crt.tpl"
  destination = "/secrets/tls.crt"
}

template {
  source      = "/templates/tls.key.tpl"
  destination = "/secrets/tls.key"
}

template {
  source      = "/templates/ca.crt.tpl"
  destination = "/secrets/ca.crt"
}

template {
  source      = "/templates/admin_username.tpl"
  destination = "/secrets/admin_username"
}

template {
  source      = "/templates/admin_password.tpl"
  destination = "/secrets/admin_password"
}