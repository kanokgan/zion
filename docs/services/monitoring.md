# Monitoring

Prometheus, Grafana and Alertmanager, designed in [ADR 0010](../decisions/0010-monitoring.md): one Prometheus per cluster, one Grafana (on the Lenovo) with a data source for each. Installed by Flux as the `kube-prometheus-stack` chart. Stages 1 and 2 are live on the Lenovo (confirmed 2026-10-29); the mini is not started.

## What runs where

| | Lenovo (`extreme`) | Mac mini (`mini`) |
|---|---|---|
| Stage | 2 (stack, alert rules, tailnet access and Telegram alerts live) | not started |
| Prometheus | 15 days or 20 GB of data, 25Gi local-path volume | planned: small, 7 days |
| Grafana | yes (stateless); admin login from the SOPS secret `grafana-admin`; tailnet only at `https://grafana-ubuntu-extreme.dove-komodo.ts.net` (Tailscale sidecar) | no: queried from the Lenovo's Grafana |
| Alertmanager | yes; sends to Telegram (config in the SOPS secret `alertmanager-config`) | no |
| Exporters | node-exporter, kube-state-metrics | the same, plus `node_exporter` on the macOS host |

Manifests: `infrastructure/base/monitoring/` (namespace, chart repository), `infrastructure/extreme/monitoring/` (HelmRelease and values, alert rules in `rules/homelab-alerts.yaml`, secret templates in `secrets/`), `clusters/extreme/monitoring.yaml` (the Flux Kustomization). Prometheus data is disposable and is not backed up (ADR 0010); Grafana keeps no state of its own.

## Open it

- Grafana: `https://grafana-ubuntu-extreme.dove-komodo.ts.net` from any tailnet device; user `admin`, password from the password manager (the value in `grafana-admin`).
- Without the tailnet, from a machine with a kubeconfig for `extreme`:
  ```sh
  kubectl --context extreme -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
  kubectl --context extreme -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090
  kubectl --context extreme -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093
  ```

## Verify it works

```sh
flux get kustomization monitoring --context extreme               # READY True
kubectl --context extreme -n monitoring get helmrelease           # READY True
kubectl --context extreme -n monitoring get pods                  # all Running
```
In Prometheus, Status, then Targets: everything `UP`, except that nothing is scraped for etcd, scheduler, controller manager and kube-proxy (disabled on purpose: k3s runs them inside one process). In Grafana, the dashboard "Node Exporter / Nodes" shows the Lenovo's CPU, memory, disk and network. The `Watchdog` alert is always firing by design.

## Alerts

Defined in `infrastructure/extreme/monitoring/rules/homelab-alerts.yaml`: disk over 80% (warning) and 90% (critical), wired link below 1 Gb/s, no GPU advertised, device plugin down, Flux reconcile errors per controller. Crash loops and node problems come from the chart's default rules. The link alert is there because the Lenovo's cable once negotiated 100 Mb/s (fixed 2026-10-18, see [hosts/ubuntu-extreme/](../../hosts/ubuntu-extreme/README.md)).

To change the Telegram bot token or chat ID, edit the secret with `sops infrastructure/extreme/monitoring/alertmanager-config.sops.yaml` (the editor opens the decrypted file and encrypts it again on save). The Secret deliberately does not use the chart's own default name, so Helm and Flux do not fight over one object. How the three secrets were created, and the templates for a rebuild: [secrets/README.md](../../infrastructure/extreme/monitoring/secrets/README.md).

## Stages (ADR 0010)

1. Stack on the Lenovo, checked through a port-forward: done (2026-10-17).
2. Alert rules, Flux scraping, tailnet access to Grafana, Telegram alerts: done, in two parts so Flux never referenced a Secret that did not exist.
3. Immich metrics and the backup jobs (the sync scripts write a last-success timestamp for node_exporter's textfile collector; alert after about 26 hours); dashboards kept in Git. Open.
4. The mini, the overview dashboard over both data sources, the dead-man's switch. Open.
5. Later: a read-only Telegram bot, logs (Loki), file browsing.

## Open items

- The NAS backup scripts do not write the last-success timestamp yet, so no alert fires when a night fails (stage 3).
- Object-level Flux readiness ("this Kustomization is not Ready") needs a kube-state-metrics custom-resource-state config for Flux; today the alert is on reconcile errors per controller. Flux dashboards also come with that.
- The GPU exporter for the GTX 1650.
- Where the dead-man's-switch heartbeat goes (healthchecks.io or Uptime Kuma).
