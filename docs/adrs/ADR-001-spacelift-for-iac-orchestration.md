# ADR-001: Spacelift for Infrastructure-as-Code Orchestration

## Status

Accepted

## Context

The illm-k8s-lab project requires a platform to manage Terraform/OpenTofu infrastructure deployments across multiple cloud providers (Azure AKS, AWS EKS). Key requirements include:

- **State management** - Secure, versioned Terraform state with rollback capability
- **Multi-cloud credentials** - Centralized management of Azure and AWS credentials
- **Stack dependencies** - Foundation networking stacks must deploy before experiment clusters
- **Policy enforcement** - Governance guardrails for infrastructure changes (aligns with Phase 2.5)
- **GitOps workflow** - Git-triggered plans with PR previews
- **Cost predictability** - Suitable for a learning/portfolio project

The project already uses ArgoCD for Kubernetes application deployment (GitOps), so the IaC platform should complement rather than overlap with ArgoCD's responsibilities.

### Options Considered

1. **Spacelift** - Multi-IaC orchestration platform with policy-as-code
2. **Terraform Cloud (HCP Terraform)** - HashiCorp's managed Terraform service
3. **Scalr** - Terraform Cloud alternative with per-run pricing
4. **env0** - Self-service infrastructure platform
5. **Self-managed** - S3/Azure Blob state backend + GitHub Actions

## Decision

**Use Spacelift** for Terraform state management and IaC orchestration.

## Rationale

### Why Spacelift

| Factor | Assessment |
|--------|------------|
| **Pricing model** | Concurrency-based (predictable), not per-resource. Free tier includes 2 users and unlimited policies. |
| **Stack dependencies** | Native support for dependency chains (foundation → experiment stacks). Critical for our multi-stack architecture. |
| **Policy-as-code** | Unlimited OPA policies on free tier. Aligns with Phase 2.5 governance learning objectives. |
| **Multi-cloud contexts** | Clean credential management via contexts. Supports Azure service principal and AWS IAM. |
| **OpenTofu support** | First-class support, future-proofs against HashiCorp licensing changes. |
| **Drift detection** | Automatic detection with optional auto-remediation. Valuable for catching out-of-band changes. |
| **State management** | S3-backed with versioning, 30-day history, and rollback capability. |

### Why Not Terraform Cloud

- **Per-resource pricing (RUM)** becomes expensive as infrastructure grows
- **Limited concurrency** on lower tiers (1-3 concurrent runs)
- **No OpenTofu support** - locked into HashiCorp licensing
- **Sentinel policies** require paid tier; OPA not supported

### Why Not Scalr

Scalr was a close second choice:
- **Simpler pricing** (per-run only, 50 free/month)
- **OpenTofu founding member** (strong community commitment)
- **Drop-in TFC replacement** (easier migration path)

However, Spacelift's stack dependency management and unlimited free policies better align with our multi-stack architecture and governance learning objectives.

### Why Not env0

- **Tier-based pricing** with RUM factors
- **Optimized for self-service** use cases (dev teams requesting infrastructure)
- Less relevant for single-person learning project

### Why Not Self-Managed

- **No drift detection** without custom tooling
- **No policy enforcement** built-in
- **Manual credential rotation** required
- Acceptable for simple projects, but misses learning opportunity for enterprise IaC patterns

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Spacelift                                │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │ spacelift-root  │  │ azure-credentials│  │ aws-credentials │ │
│  │ (administrative)│  │    (context)     │  │   (context)     │ │
│  └────────┬────────┘  └─────────────────┘  └─────────────────┘ │
│           │                                                     │
│  ┌────────▼────────┐  ┌─────────────────┐                      │
│  │azure-foundation │  │ aws-foundation  │  Foundation Stacks   │
│  │  (networking)   │  │  (networking)   │  (manual deploy)     │
│  └────────┬────────┘  └────────┬────────┘                      │
│           │                    │                                │
│  ┌────────▼────────┐  ┌────────▼────────┐                      │
│  │ exp-*-aks       │  │ exp-*-eks       │  Experiment Stacks   │
│  │ (AKS clusters)  │  │ (EKS clusters)  │  (auto-discovered)   │
│  └─────────────────┘  └─────────────────┘                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         ArgoCD                                  │
│         (Kubernetes application deployment - GitOps)            │
│                                                                 │
│  Spacelift provisions clusters → ArgoCD deploys applications    │
└─────────────────────────────────────────────────────────────────┘
```

### Responsibility Boundaries

| Layer | Tool | Responsibility |
|-------|------|----------------|
| Cloud Infrastructure | Spacelift + Terraform | VNets, subnets, AKS/EKS clusters, IAM |
| Kubernetes Platform | ArgoCD | Core platform components (cert-manager, observability) |
| Applications | ArgoCD | Experiment workloads, demo apps |
| Workflows | Argo Workflows | Experiment orchestration, load testing |

## Consequences

### Positive

- **Learning value** - Exposure to enterprise IaC orchestration patterns
- **Portfolio quality** - Demonstrates mature infrastructure management
- **Policy foundation** - OPA policies support Phase 2.5 governance experiments
- **Multi-cloud ready** - Clean credential isolation for Azure and AWS
- **State safety** - Versioned state with rollback reduces blast radius

### Negative

- **Complexity overhead** - More moving parts than self-managed state
- **Vendor dependency** - Tied to Spacelift platform (mitigated by standard Terraform)
- **Learning curve** - Spacelift concepts (stacks, contexts, policies) require upfront investment

### Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Spacelift outage blocks deployments | Foundation stacks are manual-trigger only; experiments can wait |
| Free tier limitations | 2 users sufficient for solo project; upgrade path available |
| Feature changes | Standard Terraform code remains portable to other platforms |

## Implementation

Current implementation in repository:

- `.spacelift/config.yml` - Global Spacelift configuration
- `platform/spacelift/base/main.tf` - Administrative stack managing other stacks
- `.spacelift/policies/plan-approval.rego` - OPA approval policy

### Remaining Tasks (Phase 1.2)

- [ ] Create Spacelift account and connect GitHub repo
- [ ] Create `spacelift-root` stack (administrative=true)
- [ ] Configure cloud credential contexts (Azure, AWS)
- [ ] Verify stack dependency chain works
- [ ] Document Spacelift workflow patterns

## References

- [Spacelift Documentation](https://docs.spacelift.io/)
- [Spacelift State Management](https://docs.spacelift.io/vendors/terraform/state-management)
- [Spacelift vs Terraform Cloud](https://spacelift.io/terraform-cloud-vs-spacelift)
- [Terraform Cloud Alternatives - Scalr](https://scalr.com/learning-center/selecting-a-terraform-cloud-alternative/)
- [Terraform Cloud Alternatives - env0](https://www.env0.com/blog/terraform-cloud-tfc-alternatives-comprehensive-buyers-guide)

## Decision Date

2025-12-10
