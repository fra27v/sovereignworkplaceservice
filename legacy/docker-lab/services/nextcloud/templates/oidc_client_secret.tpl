{{- with secret "kv/data/nextcloud/oidc" -}}
{{ .Data.data.client_secret }}
{{- end }}