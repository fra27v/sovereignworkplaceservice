{{- with secret "kv/data/nextcloud/db" -}}
{{ .Data.data.username }}
{{- end }}