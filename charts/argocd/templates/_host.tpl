{{/* @format */}}
{{/*
Ingress host: "argocd.<domain>". <domain> is global.domain, else the host of
Rancher's global.cattle.url (a bare IP becomes <ip>.nip.io so it still resolves).
*/}}
{{- define "argocd.host" -}}
{{- if .Values.ingress.host -}}
{{- .Values.ingress.host -}}
{{- else -}}
{{- $d := .Values.global.domain -}}
{{- if not $d -}}
{{- $d = (urlParse (.Values.global.cattle.url | default "")).hostname -}}
{{- if regexMatch "^[0-9.]+$" $d }}{{ $d = printf "%s.nip.io" $d }}{{ end -}}
{{- end -}}
{{- if not $d }}{{ fail "set global.domain (or ingress.host): no server domain found" }}{{ end -}}
{{- printf "argocd.%s" $d -}}
{{- end -}}
{{- end -}}
