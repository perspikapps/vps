<!-- @format -->

# vps-lib

A Helm **library chart** (not installable) with the helpers every app chart of this catalog shares:

- `vps-lib.host`: the Ingress host `<app>.<domain>` (`ingress.host`, else `global.domain`, else the domain of Rancher's `global.cattle.url`).
- `vps-lib.ingress`: a Traefik Ingress (class, host, backend service and port, optional TLS secret). Its `middlewares` value (empty = public) sets the route's Traefik middlewares, e.g. `kube-system-internal-only@kubernetescrd` for an internal route; `annotations` and `tlsIssuer` add the rest.

An app chart depends on it (`repository: file://../_lib`) and its `templates/ingress.yaml` is one `include`:

```yaml
{{ include "vps-lib.ingress" (dict "ctx" . "app" "argocd" "ingress" .Values.ingress
   "name" (printf "%s-argocd" .Release.Name) "service" "argocd-server" "port" 80
   "className" .Values.ingress.className) }}
```

`helm dependency update charts/<app>` vendors it (the publish workflow and `app-helm` do); the library itself is not released.
