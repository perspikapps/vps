{{/* @format */}}
{{/*
Ingress host: "hermes.<domain>". <domain> is global.domain, else the host of
Rancher's global.cattle.url (a bare IP becomes <ip>.nip.io so it still resolves).
*/}}
{{- define "hermes.host" -}}
{{- if .Values.dashboard.ingress.host -}}
{{- .Values.dashboard.ingress.host -}}
{{- else -}}
{{- $d := .Values.global.domain -}}
{{- if and (not $d) (ne (.Values.dashboard.ingress.access | default "public") "internal") -}}
{{- $d = (urlParse (.Values.global.cattle.url | default "")).hostname -}}
{{- if regexMatch "^[0-9.]+$" $d }}{{ $d = printf "%s.nip.io" $d }}{{ end -}}
{{- end -}}
{{- if not $d }}{{ fail "set global.domain (or ingress.host): no server domain found" }}{{ end -}}
{{- printf "hermes.%s" $d -}}
{{- end -}}
{{- end -}}
