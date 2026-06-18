{{- with secret "kv/data/nextcloud/db" -}}
{{ .Data.data.name }}
{{- end }}