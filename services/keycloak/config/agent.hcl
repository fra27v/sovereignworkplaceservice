pid_file = "/tmp/agent.pid"

vault {
  address = "http://vault:8200"
}

auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path   = "/config/role_id"
      secret_id_file_path = "/config/secret_id"
    }
  }

  sink "file" {
    config = {
      path = "/secrets/.vault-token"
    }
  }
}

template {
  source      = "/templates/tls.crt.ctmpl"
  destination = "/secrets/tls.crt"
}

template {
  source      = "/templates/tls.key.ctmpl"
  destination = "/secrets/tls.key"
}

template {
  source      = "/templates/ca.crt.ctmpl"
  destination = "/secrets/ca.crt"
}

template {
  source      = "/templates/keycloak.conf.ctmpl"
  destination = "/secrets/keycloak.conf"
}
template {
  source      = "/templates/db_username.ctmpl"
  destination = "/secrets/db_username"
}

template {
  source      = "/templates/db_password.ctmpl"
  destination = "/secrets/db_password"
}