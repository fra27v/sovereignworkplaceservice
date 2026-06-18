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
  source      = "/templates/db_password.ctmpl"
  destination = "/secrets/db_password"
}

template {
  source      = "/templates/tls_keystore_password.ctmpl"
  destination = "/secrets/tls_keystore_password"
}

template {
  source      = "/templates/tls_truststore_password.ctmpl"
  destination = "/secrets/tls_truststore_password"
}

template {
  source      = "/templates/config.xml.ctmpl"
  destination = "/generated/config.xml"
}

template {
  source      = "/templates/midpoint_keystore_password.ctmpl"
  destination = "/secrets/midpoint_keystore_password"
}

template {
  source      = "/templates/020-security-policy-keycloak.xml.ctmpl"
  destination = "/generated/020-security-policy-keycloak.xml"
}

template {
  source      = "/templates/030-system-configuration-security-policy.xml.ctmpl"
  destination = "/generated/030-system-configuration-security-policy.xml"
}

template {
  source      = "/templates/midpoint_adm_password.ctmpl"
  destination = "/secrets/midpoint_adm_password"
}

template {
  source      = "/templates/orangehrm-db-username.ctmpl"
  destination = "/secrets/orangehrm_db_username"
}

template {
  source      = "/templates/orangehrm-db-password.ctmpl"
  destination = "/secrets/orangehrm_db_password"
}

template {
  source      = "/templates/keycloak_connector_client_id.ctmpl"
  destination = "/secrets/keycloak_connector_client_id"
}

template {
  source      = "/templates/keycloak_connector_client_secret.ctmpl"
  destination = "/secrets/keycloak_connector_client_secret"
}