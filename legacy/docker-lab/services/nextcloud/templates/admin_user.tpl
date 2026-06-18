{{- with secret "kv/data/nextcloud/admin" -}}
{{ .Data.data.username }}
{{- end }}