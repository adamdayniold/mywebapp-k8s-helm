# Troubleshooting notes

Problems hit while building this repo, with cause, fix and lesson.

## Fresh cluster: Flux applied nothing (SealedSecret CRD missing)
- *Symptom:* after a rebuild, the `flux-system` Kustomization was not Ready with `SealedSecret/monitoring/grafana-admin dry-run failed: no matches for kind "SealedSecret"`, and no HelmReleases existed.
- *Cause:* the `SealedSecret` CRD is installed by the `sealed-secrets` HelmRelease, which was in the same Kustomization. Flux dry-runs the whole Kustomization first, so it failed and applied nothing.
- *Fix:* split into `infrastructure`, `monitoring` and `apps` Flux Kustomizations, with `wait: true` on `infrastructure` and `dependsOn` on the other two.
- *Lesson:* anything that uses a CRD must be in a Kustomization that waits for the thing that installs it. It only shows up on a fresh cluster, because an old cluster already has the CRD.

## 404 on the app, although the Gateway was healthy
- *Symptom:* `https://webapp.local` returned `404 page not found`, but port-forwarding to the NGF service with the right Host header worked. The NGF `svclb` pod was `Pending`.
- *Cause:* k3s's bundled Traefik held host ports 80/443, so all traffic went to Traefik, which had no routes. The 404 body was Traefik's, not the app's.
- *Fix:* create the cluster with `--k3s-arg "--disable=traefik@server:*"`.
- *Lesson:* a `Pending` `svclb` pod is not cosmetic. Check which component actually answers on the port before debugging routes.

## Duplicate resource in Kustomize *(from the earlier flat layout)*
- *Symptom:* every reconcile failed with "may not add resource with an already registered id".
- *Cause:* the same files were pulled in twice, once by `flux-system/kustomization.yaml` (`../*.yaml`) and again by the parent folder.
- *Fix:* one parent kustomization that lists everything once.
- *Lesson:* run `kubectl kustomize --load-restrictor=LoadRestrictionsNone <path>` locally before pushing.

## Pruning deleted the whole platform
- *Symptom:* after removing the `../` entries, Flux deleted every HelmRelease and no new ones appeared.
- *Cause:* pruning removes anything no longer in the build, and Flux's `path` still pointed at `flux-system/`, so the parent kustomization was never read.
- *Fix:* change `path` to `./clusters/local-k3d`.
- *Lesson:* with `prune: true`, changing what a Kustomization includes can delete live resources. Check the inventory first.

## Loki had no application logs
- *Symptom:* queries by namespace returned nothing and only the Loki canary's own logs showed up.
- *Causes:* `/var/log` was not mounted into Alloy, no namespace label existed, and the push URL named a service that did not exist.
- *Fix:* `alloy.mounts.varlog: true`, a relabel step, and the correct `monitoring-loki` URL.
- *Lesson:* check what the pipeline actually ships (label values, "start tailing file" logs) before blaming the query.
