{{/* @format */}}
{{/*
vps-lib.ingress - a Traefik Ingress for an app. Arguments (a dict):
  ctx        the chart's root context (.)
  app        the app name (the host is <app>.<domain>, see vps-lib.host)
  ingress    the chart's ingress values: className, host, middlewares (Traefik middlewares of the
             route, empty = public), annotations (extra annotations), tlsIssuer (cert-manager issuer)
  name       the Ingress name
  service    the backend Service name
  port       the backend port: a number, or a port name (a string)
  className  the ingress class
  labels     optional: pre-rendered labels (a YAML string)
  tlsSecret  optional: the TLS Secret name; adds a tls section
*/}}
{{- define "vps-lib.ingress" -}}
{{- $host := include "vps-lib.host" (dict "ctx" .ctx "app" .app "ingress" .ingress) -}}
{{- $annotations := dict -}}
{{- with .ingress.annotations }}{{ $annotations = merge $annotations . }}{{ end -}}
{{- if .ingress.middlewares }}{{ $_ := set $annotations "traefik.ingress.kubernetes.io/router.middlewares" .ingress.middlewares }}{{ end -}}
{{- if .ingress.tlsIssuer }}{{ $_ := set $annotations "cert-manager.io/cluster-issuer" .ingress.tlsIssuer }}{{ end -}}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
    name: {{ .name }}
    {{- with .labels }}
    labels:
        {{- . | nindent 8 }}
    {{- end }}
    {{- with $annotations }}
    annotations:
        {{- toYaml . | nindent 8 }}
    {{- end }}
spec:
    ingressClassName: {{ .className }}
    rules:
        - host: {{ $host }}
          http:
              paths:
                  - path: /
                    pathType: Prefix
                    backend:
                        service:
                            name: {{ .service }}
                            port:
                                {{- if kindIs "string" .port }}
                                name: {{ .port }}
                                {{- else }}
                                number: {{ .port }}
                                {{- end }}
    {{- with .tlsSecret }}
    tls:
        - hosts:
              - {{ $host }}
          secretName: {{ . }}
    {{- end }}
{{- end -}}
