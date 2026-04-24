{{- with secret "kv/data/nextcloud/redis" -}}
{{ .Data.data.password }}
{{- end }}