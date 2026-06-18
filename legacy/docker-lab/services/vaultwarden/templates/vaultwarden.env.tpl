DOMAIN=https://passwords.internal

SIGNUPS_ALLOWED=false
INVITATIONS_ALLOWED=true

SSO_ENABLED=true
SSO_ONLY=false
SSO_PKCE=true

SSO_CLIENT_ID='{{ with secret "kv/data/vaultwarden/oidc" }}{{ .Data.data.client_id }}{{ end }}'
SSO_CLIENT_SECRET='{{ with secret "kv/data/vaultwarden/oidc" }}{{ .Data.data.client_secret }}{{ end }}'
SSO_SCOPES='openid email profile offline_access'
SSO_AUTHORITY=https://auth.internal/realms/sovereign
SSO_USERNAME_CLAIM=preferred_username
SSO_EMAIL_CLAIM=email

ADMIN_TOKEN='{{ with secret "kv/data/vaultwarden/admin" }}{{ .Data.data.admin_token }}{{ end }}'