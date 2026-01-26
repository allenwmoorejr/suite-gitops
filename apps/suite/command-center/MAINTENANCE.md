# Command Center CI/CD Maintenance Guide

This document explains the automated image tag update system and how to maintain it.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            CI/CD PIPELINE FLOW                               │
└─────────────────────────────────────────────────────────────────────────────┘

1. CODE COMMIT
   └──> Jenkins detects change (webhook or poll)

2. JENKINS BUILD
   └──> Builds Next.js app
   └──> Creates Docker image with timestamp tag (YYYYMMDD-HHMMSS)
   └──> Pushes to registry.suite.home.arpa:5000

3. IMAGE DETECTION (Flux Image Automation)
   └──> ImageRepository scans registry every 1 minute
   └──> Detects new tag

4. TAG SELECTION
   └──> ImagePolicy evaluates new tag against filter
   └──> Selects latest timestamp using numerical sorting

5. GIT UPDATE
   └──> ImageUpdateAutomation updates patch-helmrelease-values.yaml
   └──> Commits with message: "chore(command-center): update image tags"
   └──> Pushes to main branch

6. DEPLOYMENT
   └──> Flux GitRepository detects new commit
   └──> Kustomization reconciles changes
   └──> HelmRelease upgrades deployment with new image
```

## File Structure

```
apps/suite/command-center/
├── MAINTENANCE.md                    # This file
├── helmrelease.yaml                  # Main Helm release definition
├── kustomization.yaml                # Kustomize entry point
├── chart/                            # Helm chart
│   ├── Chart.yaml
│   ├── values.yaml                   # Default values (used as fallback)
│   └── templates/
├── patches/
│   └── patch-helmrelease-values.yaml # ⭐ IMAGE TAGS LIVE HERE
└── image-automation/
    ├── kustomization.yaml            # Resources list
    ├── imagerepository-ui.yaml       # Scans registry for UI tags
    ├── imagerepository-api.yaml      # Scans registry for API tags
    ├── imagepolicy-ui.yaml           # Selects latest UI tag
    ├── imagepolicy-api.yaml          # Selects latest API tag
    └── imageupdateautomation.yaml    # Commits tag updates to Git
```

## How Image Automation Works

### 1. ImageRepository
Scans the container registry for available tags.

```yaml
# image-automation/imagerepository-ui.yaml
spec:
  image: registry.suite.home.arpa:5000/suite-command-center-ui
  interval: 1m0s    # Scan frequency
  insecure: true    # Allow HTTP (non-TLS) registry
```

**Check status:**
```bash
flux get image repository -n flux-system
kubectl describe imagerepository command-center-ui -n flux-system
```

### 2. ImagePolicy
Selects which tag to use based on a filter pattern.

```yaml
# image-automation/imagepolicy-ui.yaml
spec:
  filterTags:
    pattern: '^(?P<prefix>.*-)?(?P<ts>\d{8}-\d{4,6})$'  # Match timestamp tags
    extract: '$ts'                                       # Extract sortable part
  policy:
    numerical:
      order: asc    # Higher numbers = newer (20260121 > 20260120)
```

**Check status:**
```bash
flux get image policy -n flux-system
# Shows selected tag for each policy
```

### 3. ImageUpdateAutomation
Commits tag updates to the Git repository.

```yaml
# image-automation/imageupdateautomation.yaml
spec:
  update:
    path: ./apps/suite/command-center  # Where to look for markers
    strategy: Setters                   # Use marker comments
  git:
    push:
      branch: main
```

**Check status:**
```bash
flux get image update -n flux-system
kubectl logs -n flux-system deploy/image-automation-controller
```

### 4. Update Markers
The magic happens via special comments in YAML files:

```yaml
# patches/patch-helmrelease-values.yaml
tag: 20260114-1050  # {"$imagepolicy": "flux-system:command-center-ui:tag"}
```

The marker format: `# {"$imagepolicy": "NAMESPACE:POLICY_NAME:FIELD"}`
- `NAMESPACE`: Where ImagePolicy lives (`flux-system`)
- `POLICY_NAME`: Name of the ImagePolicy (`command-center-ui`)
- `FIELD`: What to extract (`tag`, `name`, or nothing for full reference)

## Common Operations

### Check Current Image Status
```bash
# See all image policies and their selected tags
flux get image policy -A

# See what tags are available in registry
flux get image repository -A

# See recent automation commits
flux get image update -A
```

### Force Immediate Reconciliation
```bash
# After pushing a new image, force immediate scan
flux reconcile image repository command-center-ui -n flux-system

# Force policy re-evaluation
flux reconcile image policy command-center-ui -n flux-system

# Force automation to run
flux reconcile image update command-center -n flux-system
```

### Manually Update a Tag (Override Automation)
If you need to pin a specific version:

1. Edit `patches/patch-helmrelease-values.yaml`
2. Change the tag value (automation will still try to update it)
3. To permanently pin, remove the marker comment:
   ```yaml
   # Before (automated):
   tag: 20260114-1050  # {"$imagepolicy": "flux-system:command-center-ui:tag"}

   # After (pinned):
   tag: 20260114-1050
   ```

### Rollback to Previous Version
```bash
# Find previous tag in Git history
git log --oneline patches/patch-helmrelease-values.yaml

# Revert to specific commit
git revert <commit-hash>
git push

# Or manually set the old tag (remove marker to prevent re-update)
```

### Add a New Service Image
1. Create `image-automation/imagerepository-newservice.yaml`:
   ```yaml
   apiVersion: image.toolkit.fluxcd.io/v1beta2
   kind: ImageRepository
   metadata:
     name: newservice
     namespace: flux-system
   spec:
     image: registry.suite.home.arpa:5000/suite-newservice
     interval: 1m0s
     insecure: true
   ```

2. Create `image-automation/imagepolicy-newservice.yaml`:
   ```yaml
   apiVersion: image.toolkit.fluxcd.io/v1beta2
   kind: ImagePolicy
   metadata:
     name: newservice
     namespace: flux-system
   spec:
     imageRepositoryRef:
       name: newservice
     filterTags:
       pattern: '^(?P<ts>\d{8}-\d{4,6})$'
       extract: '$ts'
     policy:
       numerical:
         order: asc
   ```

3. Add to `image-automation/kustomization.yaml`:
   ```yaml
   resources:
     - imagerepository-newservice.yaml
     - imagepolicy-newservice.yaml
   ```

4. Add marker to your values:
   ```yaml
   tag: latest  # {"$imagepolicy": "flux-system:newservice:tag"}
   ```

## Troubleshooting

### Automation Not Updating Tags

1. **Check ImageRepository can reach registry:**
   ```bash
   kubectl describe imagerepository command-center-ui -n flux-system
   # Look for "scan succeeded" or error messages
   ```

2. **Check ImagePolicy is selecting tags:**
   ```bash
   flux get image policy command-center-ui -n flux-system
   # Should show "Latest image: registry.../...:TAG"
   ```

3. **Check ImageUpdateAutomation can push to Git:**
   ```bash
   kubectl logs -n flux-system deploy/image-automation-controller
   # Look for authentication or permission errors
   ```

4. **Verify markers are correct:**
   ```bash
   grep -r 'imagepolicy' apps/suite/command-center/
   # Ensure marker format is exactly right
   ```

### Registry Connection Issues

If using an insecure (HTTP) registry:
- Ensure `insecure: true` is set in ImageRepository
- The image-reflector-controller must be able to reach the registry
- Check network policies allow egress to registry

### Tag Not Being Selected

Check your filter pattern matches your tag format:
```bash
# Test regex against your tags
echo "20260114-1050" | grep -P '^(?P<ts>\d{8}-\d{4,6})$'
```

## Related Files

| File | Purpose |
|------|---------|
| `clusters/home/flux-system/gotk-components.yaml` | Flux controllers (includes image-reflector and image-automation) |
| `clusters/home/flux-system/gotk-sync.yaml` | Git repository and main kustomization |
| `cc-ui-bump-values.sh` | Legacy manual tag bump script (deprecated by automation) |

## Jenkins Integration

The Jenkins pipeline at `dashboard-k3s/suite-command-center/services/command-center-ui/Jenkinsfile`:
- Builds images with timestamp tags: `YYYYMMDD-HHMMSS`
- Pushes to `registry.suite.home.arpa:5000`
- Currently also does `kubectl set image` (can be removed once automation is verified)

After automation is working, you can simplify Jenkins to just build and push - Flux handles deployment.

## Monitoring

Set up alerts for:
- ImageRepository scan failures
- ImageUpdateAutomation push failures
- HelmRelease reconciliation failures

```bash
# Quick health check
flux get all -A | grep -E '(False|Unknown)'
```
