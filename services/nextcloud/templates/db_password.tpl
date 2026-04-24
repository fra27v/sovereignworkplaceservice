{{- with secret "kv/data/nextcloud/db" -}}
{{ .Data.data.password }}
{{- end }}