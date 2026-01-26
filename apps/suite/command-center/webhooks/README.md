# Command Center Webhook Automation

This directory contains the configuration for automated CI/CD webhooks.

## Architecture

```
GitHub Push Event
       │
       ▼
Cloudflare Tunnel (jenkins-webhook.allenwmoorejr.org)
       │
       ▼
Jenkins (builds image, pushes to registry)
       │
       ├──► GitHub Deployment Status API (marks deployment as pending/success/failure)
       │
       ▼
Flux Image Automation (detects new tag, commits to GitOps)
       │
       ▼
Flux HelmRelease (deploys to K8s)
       │
       ▼
Flux Notification Controller
       │
       └──► External webhook (status page, GitHub deployment status)
```

## Setup Steps

### 1. Create Cloudflare Tunnel

```bash
# Login to Cloudflare (one-time)
cloudflared tunnel login

# Create tunnel
cloudflared tunnel create jenkins-webhook

# This creates credentials at ~/.cloudflared/<TUNNEL_ID>.json
```

### 2. Configure DNS

```bash
# Route your domain to the tunnel
cloudflared tunnel route dns jenkins-webhook jenkins-webhook.allenwmoorejr.org
```

### 3. Apply Kubernetes Resources

```bash
# Create the tunnel secret
kubectl create secret generic cloudflare-tunnel-jenkins \
  --from-file=credentials.json=$HOME/.cloudflared/<TUNNEL_ID>.json \
  -n jenkins

# Apply the tunnel deployment and Flux notifications
kubectl apply -k /home/wayne/suite-gitops/apps/suite/command-center/webhooks/
```

### 4. Configure GitHub Webhook

In your GitHub repo settings:
- URL: `https://jenkins-webhook.allenwmoorejr.org/github-webhook/`
- Content type: `application/json`
- Secret: (configure in Jenkins)
- Events: Push, Pull Request

## Files

- `cloudflare-tunnel.yaml` - Tunnel deployment for Jenkins webhook exposure
- `flux-notification-provider.yaml` - Flux notification provider for GitHub
- `flux-alert.yaml` - Alert rules for HelmRelease events
- `webhook-relay-configmap.yaml` - Script for custom webhook relay
