{{/* @format */}}
{{/*
vps-lib.host - the Ingress host of an app: "<app>.<domain>". Arguments (a dict):
  ctx      the chart's root context (.)
  app      the app name
  ingress  the chart's ingress values (a host there wins)
<domain> is global.domain, else the host of Rancher's global.cattle.url (a bare IP becomes
<ip>.nip.io so it still resolves).
*/}}
{{- define "vps-lib.host" -}}
{{- if .ingress.host -}}
{{- .ingress.host -}}
{{- else -}}
{{- $d := .ctx.Values.global.domain -}}
{{- if not $d -}}
{{- $d = (urlParse (.ctx.Values.global.cattle.url | default "")).hostname -}}
{{- if regexMatch "^[0-9.]+$" $d }}{{ $d = printf "%s.nip.io" $d }}{{ end -}}
{{- end -}}
{{- if not $d }}{{ fail "set global.domain (or ingress.host): no server domain found" }}{{ end -}}
{{- printf "%s.%s" .app $d -}}
{{- end -}}
{{- end -}}
