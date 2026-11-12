# Design notes

## Repository layout

Flux's `flux-system` Kustomization (path `./clusters/local-k3d`, `prune: true`) deploys three more Flux Kustomizations, defined in `clusters/local-k3d/`: `infrastructure` (with `wait: true`), then `monitoring` and `apps`, which both `dependsOn` it. Every folder has its own `kustomization.yaml` listing its files.

```
clusters/local-k3d/       Entry point: flux-system/ (bootstrap files) + the folders below
infrastructure/
  sources/                HelmRepositories and the gateway-api GitRepository
  crds/                   Gateway API CRDs
  controllers/            cert-manager, sealed-secrets, metrics-server, VPA, NGINX Gateway Fabric
  namespace-config/       HelmRelease for charts/infrastructure-namespace
monitoring/               kube-prometheus-stack, Loki, Grafana Alloy, namespace
apps/webapp/              HelmRelease for charts/mywebapp
charts/
  mywebapp/               App Deployment, Mongo StatefulSet, Gateway/HTTPRoute, cert, HPA, VPA, SealedSecret
  infrastructure-namespace/  LimitRange, ResourceQuota, NetworkPolicy, RBAC, cert-manager Issuers
scripts/                  bootstrap.sh, seal-secrets.sh
secrets/                  Raw secrets (git-ignored)
```

Install order is set with `dependsOn`: `infra` waits for cert-manager and sealed-secrets, `grafana-alloy` for Loki, and `mywebapp` for `infra`, NGF and the autoscalers.

## Design decisions

- **One Flux Kustomization per concern.** `infrastructure`, `monitoring` and `apps` each have their own folder and their own Flux Kustomization. `infrastructure` uses `wait: true`, so `monitoring` and `apps` start only after its HelmReleases are healthy. That guarantees CRDs such as `SealedSecret` exist before anything uses them, which makes a rebuild from scratch work with no manual steps.
- **Explicit ordering with `dependsOn`, also between HelmReleases.** The app does not install until its certificate issuers, gateway controller and autoscalers exist.
- **Traefik disabled at cluster creation.** `bootstrap.sh` passes `--disable=traefik@server:*` to k3d, so NGINX Gateway Fabric is the only thing on ports 80/443.
- **Git-sourced charts use `reconcileStrategy: Revision`**, so a chart change in Git is picked up without bumping the chart version.
- **Values via `chart.spec.valuesFiles`.** The HelmRelease lists both `values.yaml` and `values-k3d.yaml`, because `valuesFiles` replaces the chart defaults. `values-k3d.yaml` holds only the local overrides.
- **VPA on memory, HPA on CPU.** `vpa.controlledResources: ["memory"]` keeps the two autoscalers from fighting.
- **File-based log collection.** Alloy reads node log files and relabels from the path, instead of using Kubernetes API discovery. It needs `/var/log` mounted into the Alloy pod.
- **Sealed Secrets over plain Secrets.** Encrypted values are safe to commit.

## Secrets workflow

Plaintext secrets never go in the chart or in Git. Raw files live in `secrets/` (git-ignored, as are `*raw*.yaml` and `*.pem`).

1. Write the plaintext Secret as `secrets/mongo-secret-raw.yaml` or `secrets/grafana-admin-raw.yaml`, with a literal namespace.
2. Seal them:
   ```bash
   scripts/seal-secrets.sh [--refresh-cert]
   ```
   This writes `charts/mywebapp/templates/secret.yaml` and `monitoring/grafana-admin-secret.yaml`, using the cert in `secrets/pub-cert.pem`.
3. Commit the SealedSecrets. The controller (`kube-system-sealed-secrets` in `kube-system`) decrypts them in-cluster.

Sealed secrets are bound to the cluster's private key, which lives in the cluster. Stopping and starting the cluster keeps it; deleting the cluster loses it. To keep secrets valid across rebuilds, back up the key to `secrets/sealed-secrets-key.yaml`; `bootstrap.sh` applies it before Flux installs the controller, so the controller reuses the old key and the committed SealedSecrets still decrypt. The controller rotates its key every 30 days and keeps the old ones, so refresh the backup now and then:

```bash
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > secrets/sealed-secrets-key.yaml
```

`seal-secrets.sh` is only run by hand: when a password changes (edit the raw file first), or after a rebuild without the key backup (`--refresh-cert` fetches the new cluster's certificate). Flux and `bootstrap.sh` never run it. Treat the key backup like a password: it is git-ignored, and anyone holding it can decrypt the SealedSecrets.

## Observability

- **Metrics:** Prometheus scrapes cAdvisor, kube-state-metrics and node-exporter, and the app's own `/api/metrics` endpoint through a ServiceMonitor (`charts/mywebapp/templates/servicemonitor.yaml`), which gives request counts and latency per route.
- **Logs:** Alloy tails `/var/log/pods/*/*/*.log` on each node, derives `namespace`, `pod` and `container` labels from the file path, strips the CRI prefix (`stage.cri`), and pushes to Loki. Grafana reads Loki through a data source provisioned in `monitoring/kube-prometheus-stack.yaml`. The app writes one JSON line per request, so `{namespace="application", container="webapp"} | json | status >= 400` filters by field. Example for Mongo: `{namespace="application", pod=~"mongo.*"}`.
- **Dashboards:** Grafana ships the kube-prometheus-stack dashboards, plus a provisioned "Webapp Metrics" dashboard (request rate, error rate, p95 latency per route). It is stored as a ConfigMap in `monitoring/dashboards/webapp-metrics.yaml` and loaded by Grafana's sidecar through the `grafana_dashboard` label. Grafana has no persistence, so a dashboard drawn in the UI is lost on restart: export the JSON and commit it instead.
