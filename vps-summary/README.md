<!-- @format -->

# vps-summary

Prints the final connection info, Tailscale URL, and Cockpit/Rancher
credentials at the end of a `dispatch.sh` run. `dispatch.sh` runs it
automatically; re-run it any time afterwards to print the same summary
again:

```sh
sudo bash /opt/vps-setup/vps-summary/run.sh
```

Not an installable step itself — excluded from `dispatch.sh`'s feature
discovery.

## Tests

```sh
bats test.bats
```

Covers `run.sh`'s syntax and the `zz_use`/`vps-common` wiring, plus
`dispatch-steps.sh`'s syntax and `package.json`'s `bin` field. Actually
printing a real summary needs a live install to read credentials/state
from - see the root README's [Tests](../README.md#tests) section for the
full picture.
