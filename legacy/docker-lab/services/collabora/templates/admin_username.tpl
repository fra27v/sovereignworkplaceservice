{{- with secret "kv/data/collabora" -}}
{{ .Data.data.admin_username }}
{{- end }}