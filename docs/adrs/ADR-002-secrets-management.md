# ADR-002: Secrets Management with External Secrets Operator + Vault

## Status

Accepted

## Context

The illm-k8s-lab project requires a robust secrets management strategy that:

1. **Supports cloud deployments early** - Crossplane and Spacelift need credentials to provision Azure/AWS resources
2. **Enables GitOps workflows** - Secrets must be declaratively managed without storing sensitive data in Git
3. **Provides centralized management** - Single source of truth for all secrets
4. **Supports rotation** - Automatic credential rotation without application restarts
5. **Works locally and in cloud** - Same patterns for Kind and AKS/EKS clusters

### The Bootstrap Problem

Cloud credentials are needed to deploy Vault, but Vault is typically where we'd store credentials. This creates a chicken-and-egg problem.

### Options Considered

1. **Manual Kubernetes Secrets** - Create secrets via kubectl (not GitOps-friendly)
2. **Sealed Secrets** - Encrypt secrets in Git (no central management, no rotation)
3. **SOPS + Age/KMS** - Encrypt secrets in Git (complex key management)
4. **External Secrets Operator + Cloud Secret Managers** - Sync from Azure KV/AWS SM
5. **Vault Agent Sidecar** - Inject secrets at pod runtime (per-workload config)
6. **Vault CSI Provider** - Mount secrets as volumes (requires CSI driver)

## Decision

**Use External Secrets Operator (ESO) as the primary secrets synchronization mechanism**, with a two-phase approach:

### Phase 1: Bootstrap (Cloud Secret Managers → ESO → K8s Secrets)

Use cloud-native secret managers for initial bootstrap:
- Azure Key Vault for Azure credentials
- AWS Secrets Manager for AWS credentials
- ESO syncs these to Kubernetes Secrets
- Enables Crossplane providers and Vault deployment

### Phase 2: Production (Vault → ESO → K8s Secrets)

Migrate to Vault as the central secrets store:
- All secrets consolidated in Vault
- ESO continues as the sync mechanism
- Vault provides dynamic credentials, rotation, audit logging
- Cloud secret managers remain for ESO authentication only

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     BOOTSTRAP (Phase 3.1)                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────────┐          ┌──────────────────┐                │
│  │ Azure Key Vault  │          │ AWS Secrets Mgr  │                │
│  │                  │          │                  │                │
│  │ azure-sp-creds   │          │ aws-iam-creds    │                │
│  └────────┬─────────┘          └────────┬─────────┘                │
│           │                             │                          │
│           │    Workload Identity        │    IRSA                  │
│           │                             │                          │
│           └──────────────┬──────────────┘                          │
│                          ▼                                         │
│              ┌───────────────────────┐                             │
│              │ External Secrets      │                             │
│              │ Operator              │                             │
│              │                       │                             │
│              │ ClusterSecretStore:   │                             │
│              │ - azure-keyvault      │                             │
│              │ - aws-secretsmanager  │                             │
│              └───────────┬───────────┘                             │
│                          ▼                                         │
│              ┌───────────────────────┐                             │
│              │ Kubernetes Secrets    │                             │
│              │                       │                             │
│              │ crossplane-system/    │                             │
│              │ - azure-credentials   │                             │
│              │ - aws-credentials     │                             │
│              └───────────────────────┘                             │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              │ Enables deployment of...
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     PRODUCTION (Phase 3.2+)                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│              ┌───────────────────────┐                             │
│              │ HashiCorp Vault       │                             │
│              │                       │                             │
│              │ Secrets Engines:      │                             │
│              │ - KV v2 (static)      │                             │
│              │ - Database (dynamic)  │                             │
│              │ - PKI (certificates)  │                             │
│              │                       │                             │
│              │ Auth Methods:         │                             │
│              │ - Kubernetes          │                             │
│              │ - AppRole (CI/CD)     │                             │
│              └───────────┬───────────┘                             │
│                          │                                         │
│                          │ Kubernetes Auth                         │
│                          ▼                                         │
│              ┌───────────────────────┐                             │
│              │ External Secrets      │                             │
│              │ Operator              │                             │
│              │                       │                             │
│              │ ClusterSecretStore:   │                             │
│              │ - vault               │                             │
│              └───────────┬───────────┘                             │
│                          ▼                                         │
│              ┌───────────────────────┐                             │
│              │ Kubernetes Secrets    │  Auto-rotated               │
│              │                       │  Audit logged               │
│              │ All experiment        │  Policy controlled          │
│              │ secrets               │                             │
│              └───────────────────────┘                             │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Rationale

### Why External Secrets Operator

| Factor | ESO | Vault Agent | Vault CSI | Sealed Secrets |
|--------|-----|-------------|-----------|----------------|
| GitOps-friendly | Yes (ExternalSecret CRs) | No (annotations) | Partial | Yes |
| Central management | Yes (via backend) | Yes | Yes | No |
| Multiple backends | Yes (Vault, Azure, AWS, GCP) | Vault only | Vault only | N/A |
| Rotation support | Yes (refreshInterval) | Yes | Limited | No |
| No per-pod config | Yes | No (annotations per pod) | No (CSI volume per pod) | Yes |
| Works with any workload | Yes | Requires sidecar | Requires CSI driver | Yes |

### Why Two-Phase Approach

1. **Bootstrap phase** solves chicken-and-egg:
   - Cloud secret managers don't need Kubernetes to exist
   - ESO authenticates via Workload Identity/IRSA (no static credentials)
   - Vault can be deployed using ESO-synced credentials

2. **Production phase** provides:
   - Dynamic credentials (database, PKI)
   - Centralized audit logging
   - Fine-grained access policies
   - Secret versioning and rotation

### Why Keep Cloud Secret Managers

Even after Vault is deployed, cloud secret managers are retained for:
- ESO authentication to Vault (via Workload Identity/IRSA)
- Disaster recovery (if Vault is unavailable)
- Cloud-native service integration (some Azure/AWS services prefer their native secret managers)

## Implementation

### ClusterSecretStore Resources

```yaml
# Azure Key Vault backend (bootstrap)
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: azure-keyvault
spec:
  provider:
    azurekv:
      authType: WorkloadIdentity
      vaultUrl: "https://illm-k8s-lab-kv.vault.azure.net"
      serviceAccountRef:
        name: external-secrets
        namespace: external-secrets

# AWS Secrets Manager backend (bootstrap)
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secretsmanager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets

# Vault backend (production)
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault
spec:
  provider:
    vault:
      server: "http://vault.vault:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "external-secrets"
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
```

### ExternalSecret Example

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: azure-credentials
  namespace: crossplane-system
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: azure-keyvault  # or "vault" after migration
    kind: ClusterSecretStore
  target:
    name: azure-credentials
    creationPolicy: Owner
  data:
    - secretKey: credentials
      remoteRef:
        key: crossplane-azure-credentials
```

## Consequences

### Positive

- **GitOps-compatible**: All secret references are declarative CRs in Git
- **Flexible backends**: Can use cloud-native or Vault without changing application code
- **Automatic rotation**: `refreshInterval` keeps secrets current
- **Centralized audit**: Vault provides complete audit trail
- **No static credentials in cluster**: ESO uses Workload Identity/IRSA

### Negative

- **Additional component**: ESO adds operational overhead
- **Two systems initially**: Cloud secret managers + Vault during transition
- **Learning curve**: Teams must understand ESO + Vault concepts

### Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| ESO unavailable | Secrets remain in K8s (no auto-rotation until ESO recovers) |
| Vault unavailable | Bootstrap secrets in cloud secret managers as fallback |
| Secret sync delay | Configure appropriate `refreshInterval` for sensitivity |
| Credential exposure in logs | Use `spec.target.template` to format secrets appropriately |

## Alternatives Not Chosen

### Sealed Secrets
- **Rejected because**: No central management, no rotation, secrets encrypted in Git but still version-controlled

### SOPS with Age/KMS
- **Rejected because**: Complex key management, no dynamic credentials, requires tooling in CI/CD

### Vault Agent Only
- **Rejected because**: Requires per-pod annotations, not GitOps-friendly, complex sidecar management

### Vault CSI Provider Only
- **Rejected because**: Requires CSI driver, complex volume management, limited rotation support

## References

- [External Secrets Operator Documentation](https://external-secrets.io/)
- [ESO Azure Key Vault Provider](https://external-secrets.io/latest/provider/azure-key-vault/)
- [ESO AWS Secrets Manager Provider](https://external-secrets.io/latest/provider/aws-secrets-manager/)
- [ESO Vault Provider](https://external-secrets.io/latest/provider/hashicorp-vault/)
- [HashiCorp Vault Kubernetes Auth](https://developer.hashicorp.com/vault/docs/auth/kubernetes)

## Decision Date

2025-12-10
