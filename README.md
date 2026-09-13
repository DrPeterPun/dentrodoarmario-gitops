# Dentro do Armário — GitOps

Argo CD deploys what is in this repository. The two Minecraft servers use the public `itzg/minecraft-server` image, so their full deploy config lives here. There is no application-repo CI for them: change YAML in Git, Argo CD syncs the cluster.

```
bootstrap/                 # one-time Argo CD install
clusters/in-cluster/       # AppProject, ApplicationSet, local-storage StorageClass
apps/batalha-naval/
  base/                    # Deployment, Service, PV, PVC
  overlays/production/
apps/disney-bros/
  base/
  overlays/production/
```

ApplicationSet creates one Application per overlay:

| Overlay | Argo CD app | Namespace |
|---|---|---|
| `apps/batalha-naval/overlays/production` | `batalha-naval-production` | `batalha-naval-production` |
| `apps/disney-bros/overlays/production` | `disney-bros-production` | `disney-bros-production` |

There is no staging overlay. Each world is bound to a host path on node `dentrodoarmario` (`/home/serverino/mc_batalhanaval` and `/home/serverino/mc_disneybros`). A second environment would need different disks and a different LAN port/IP.

Batalha Naval is exposed on LAN `192.168.1.101:25566` (container still listens on `25565`). Disney Bros is `192.168.1.101:25565`.

## Bootstrap

Use server-side apply for the Argo CD install. The ApplicationSet CRD is larger than
kubectl's client-side `last-applied-configuration` annotation limit (256KiB), so a
plain `kubectl apply -k` can leave Argo CD running without `applicationsets.argoproj.io`.

```bash
kubectl apply --server-side -k bootstrap/argo-cd
kubectl wait --for=condition=Available -n argocd deployment/argocd-server --timeout=180s
kubectl wait --for=condition=Available -n argocd deployment/argocd-applicationset-controller --timeout=180s
kubectl apply -f bootstrap/root-app.yaml
```

If these workloads already run in another namespace (for example `default`), the existing PVCs stay bound to the old namespace. Move or recreate the claim in the new namespace, or keep the old objects and let Argo CD adopt them after you annotate them.

## Change what is running

Edit the overlay (or base env values) and merge. Typical changes:

- Image tag in `overlays/production/kustomization.yaml` (`itzg/minecraft-server`)
- Fabric `VERSION`, `MEMORY`, or `MOTD` in `base/deployment.yaml`

Or run **Actions → Update image tag** with app `batalha-naval` or `disney-bros`, environment `production`, image `itzg/minecraft-server`, and a tag such as `java21`.

## Validate locally

```bash
kubectl kustomize apps/batalha-naval/overlays/production
kubectl kustomize apps/disney-bros/overlays/production
```
