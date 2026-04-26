{{- with secret "pki/issue/internal-dot" "common_name=office.internal" "ttl=24h" -}}
{{ .Data.private_key }}
{{- end }}