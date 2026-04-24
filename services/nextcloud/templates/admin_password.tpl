{{- with secret "kv/data/nextcloud/admin" -}}
{{ .Data.data.password }}
{{- end }}