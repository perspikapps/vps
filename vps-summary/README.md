<!-- @format -->

# summary

Prints the final connection info, Tailscale URL, and
Cockpit/Rancher/ArgoCD/Epinio credentials at the end of a `dispatch.sh`
run. `dispatch.sh` runs it automatically; re-run it any time afterwards
to print the same summary again:

```sh
sudo bash /opt/vps-setup/summary/run.sh
```

Not an installable step itself — excluded from `dispatch.sh`'s feature
discovery.
