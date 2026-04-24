pid_file = "/tmp/pidfile"

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
      path = "/tmp/token"
    }
  }
}

vault {
  address = "http://vault:8200"
}

template {
  source      = "/templates/db_name.tpl"
  destination = "/secrets/db_name"
}

template {
  source      = "/templates/db_user.tpl"
  destination = "/secrets/db_username"
}

template {
  source      = "/templates/db_password.tpl"
  destination = "/secrets/db_password"
}

template {
  source      = "/templates/redis_password.tpl"
  destination = "/secrets/redis_password"
}

template {
  source      = "/templates/admin_user.tpl"
  destination = "/secrets/admin_username"
}

template {
  source      = "/templates/admin_password.tpl"
  destination = "/secrets/admin_password"
}