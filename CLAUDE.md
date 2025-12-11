# CLAUDE.md

> Keep this file short and stable. Track progress in `TODO.md`, not here.
> Use `/compact` at ~70% context. Start sessions with "Continue from TODO.md Phase X".

## Project Overview

**illm-k8s-lab** is a learning-focused Kubernetes experiment platform for Cloud/Platform/Solutions Architect roles. It follows a phased roadmap (~72 experiments across 16 phases) documented in `TODO.md`.

## Project Structure

```
illm-k8s-lab/
├── workload-catalog/           # ArgoCD applications and Helm values
│   ├── core-app-of-apps.yaml   # Root app-of-apps
│   ├── components/             # Platform components by category
│   │   ├── core/               # cert-manager, gateway-api, argocd
│   │   ├── observability/      # prometheus, loki, otel, thanos
│   │   ├── infrastructure/     # crossplane, vault, keda
│   │   ├── messaging/          # kafka, rabbitmq, strimzi
│   │   └── ...
│   └── stacks/                 # Grouped deployments (elk, loki stack)
├── experiments/                # Individual experiment directories
│   └── {name}/
│       ├── target/argocd/      # Target cluster ArgoCD apps
│       ├── loadgen/            # Load generator configs
│       └── workflow/           # Argo Workflow definitions
├── platform/
│   └── terraform/              # Infrastructure as Code
│       ├── spacelift/          # Spacelift admin stack (manages other stacks)
│       ├── azure/foundation/   # Azure RG, Key Vault, Service Principals
│       ├── aks/                # Azure Kubernetes Service
│       └── eks/                # AWS Elastic Kubernetes Service
├── docs/
│   ├── adrs/                   # Architecture Decision Records
│   └── gitops-patterns.md      # GitOps patterns documentation
└── TODO.md                     # Master roadmap and task tracking
```

## Key Architecture Decisions

- **IaC Orchestration**: Spacelift (stack dependencies, OPA policies, drift detection)
- **Secrets Management**: External Secrets Operator + Vault (ADR-002)
- **GitOps**: ArgoCD with app-of-apps pattern
- **Home Lab**: Talos Linux on GMKtec NucBox G3 (N100, 16GB, 512GB)
- **CI/CD**: GitHub Actions primary, GitLab CI for comparison

## Current Phase

Working on **Phase 1.3 (Spacelift Setup)** and **Phase 3.1 (Bootstrap Credentials & ESO)**.

### Bootstrap Flow
1. Manual: Create `spacelift-admin` stack in Spacelift UI
2. Terraform: `spacelift-admin` creates other stacks, contexts, dependencies
3. Manual: Add ARM_* secrets to `azure-credentials` context
4. Terraform: `azure-foundation` creates RG, Key Vault, ESO service principal
5. ArgoCD: Deploy ESO, reads credentials from Key Vault

## Environments

| Environment | Purpose | Status |
|-------------|---------|--------|
| Kind | Local development | Active |
| Talos (N100) | Home lab bare metal | Hardware ordered |
| AKS | Azure cloud | Terraform ready |
| EKS | AWS cloud | Terraform ready |

## Working with This Project

### Terraform
- All infrastructure managed via Spacelift
- `platform/terraform/spacelift/` is the admin stack
- Stack dependencies enforce ordering (foundation → cluster)
- Contexts hold cloud credentials (added via Spacelift UI)

### ArgoCD
- Multi-source pattern: Helm charts + Git values
- Sync waves for dependency ordering
- `ignoreDifferences` for CRDs and webhooks
- See `docs/gitops-patterns.md` for details

### Experiments
- Follow structure in `experiments/_template/`
- Use labels: `experiment: {name}`, `cluster: target|loadgen`
- Workflows in Argo Workflows

## Commands

```bash
# Taskfile commands
task exp:run:{name}      # Run experiment
task exp:deploy:{name}   # Deploy experiment
task exp:undeploy:{name} # Cleanup experiment

# Git workflow
git push                 # Triggers Spacelift runs (autodeploy stacks)
```

