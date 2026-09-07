{{/* @format */}}
{{- define "hermes.fullname" -}}
{{ .Release.Name }}-hermes
{{- end -}}

{{- define "hermes.labels" -}}
app.kubernetes.io/name: hermes
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
