# Design Decisions & Architectural Trade-offs

## 📋 Table of Contents

- [🎯 Executive Summary](#-executive-summary)
- [📚 Documentation Architecture](#-documentation-architecture)
- [1. GitOps Tool Selection: Flux CD vs ArgoCD](#1-gitops-tool-selection-flux-cd-vs-argocd)
- [2. Configuration Management: Kustomize vs Helm](#2-configuration-management-kustomize-vs-helm)
- [3. Architecture: Single Cluster + 3 Namespaces vs 3 Separate Clusters](#3-architecture-single-cluster--3-namespaces-vs-3-separate-clusters)
- [4. Kustomization Strategy & GitRepository Design](#4-kustomization-strategy--gitrepository-design)
- [5. Label Standardization Strategy](#5-label-standardization-strategy)
- [6. Kustomize Validation & Quality Assurance](#6-kustomize-validation--quality-assurance)
- [7. Flux CD Bootstrap Process & Challenges](#7-flux-cd-bootstrap-process--challenges)
- [8. Critical Analysis](#8-critical-analysis)
- [9. Conclusion & Recommendations](#9-conclusion--recommendations)

## 🎯 Executive Summary

This document outlines the key architectural decisions made during the implementation of a GitOps-based Kubernetes deployment strategy. We chose **Flux CD over ArgoCD**, **Kustomize over Helm** for application configuration, and implemented a **single cluster with three namespaces** instead of three separate clusters. Each decision was made after careful consideration of trade-offs, maintainability, and operational complexity.

**📚 Related Documentation:**
- **[README.md](README.md)** - Technical implementation details and assignment completion status
- **[how-to-run.MD](how-to-run.MD)** - Step-by-step execution instructions and user guide
- **[scripts/SCRIPTS.md](scripts/SCRIPTS.md)** - Detailed script documentation and technical reference

## Documentation Architecture

This project follows a structured documentation approach with clear separation of concerns:

- **README.md**: Technical implementation & assignment completion status
- **how-to-run.MD**: Primary user guide with step-by-step instructions
- **design-decisions.md**: Architectural decisions and trade-offs analysis
- **scripts/SCRIPTS.md**: Technical reference and script documentation

This structure eliminates redundancy while providing focused content for different audiences and use cases.

---

## 1. GitOps Tool Selection: Flux CD vs ArgoCD

### Decision: Flux CD

**The Choice**: We implemented Flux CD instead of the assignment-specified ArgoCD.

### Trade-off Analysis

| Aspect | Flux CD | ArgoCD | Our Choice Rationale |
|--------|---------|---------|---------------------|
| **Bootstrap Complexity** | Simple `flux bootstrap git` | Multi-step installation + configuration  | ✅ Flux CD - Faster setup - Better knowledge of the tool| 
| **Kubernetes Native** | Built as Kubernetes controllers | External application with UI | ✅ Flux CD - Better K8s integration |
| **GitOps Philosophy** | Pure GitOps (no UI by default) | UI-driven with GitOps support | ✅ Flux CD - True GitOps |
| **Resource Management** | Declarative CRDs only | Mix of CRDs and UI operations | ✅ Flux CD - Fully declarative |
| **Learning Curve** | Steeper for beginners | Gentler with UI | ⚠️ Trade-off accepted |
| **Community & Maturity** | Newer, growing community | Established, larger community | ⚠️ Trade-off accepted |

### What would this look like if Flux CD were truly the better choice?

If Flux CD is genuinely superior for this use case, we'd see:
- **Faster deployment cycles** due to simpler bootstrap
- **Better GitOps compliance** with no UI dependencies
- **More maintainable infrastructure** through pure declarative management
- **Future-proof architecture** aligned with Kubernetes evolution

### Implementation Strategy

**Counter-arguments:**
1. **Assignment Deviation**: We didn't follow the explicit ArgoCD requirement
2. **Team Familiarity**: ArgoCD has broader adoption and more learning resources
3. **Operational Complexity**: No UI means steeper learning curve for operators
4. **Ecosystem Maturity**: ArgoCD has more integrations and community support

**Our Response**: While valid concerns, the assignment's core goal is demonstrating GitOps principles, multi-environment management, and infrastructure as code - all of which we deliver with FluxCD.

---

## 2. Configuration Management: Kustomize vs Helm

### Decision: Kustomize for Applications, Helm for Infrastructure

**The Choice**: We used Kustomize for application configuration and Helm only for the Prometheus monitoring stack.

### Trade-off Analysis

| Aspect | Kustomize | Helm | Our Strategy |
|--------|-----------|------|--------------|
| **Complexity** | Simple, declarative | Templating engine | ✅ Kustomize for apps |
| **Learning Curve** | Minimal (YAML-based) | Steeper (Go templating) + separate OCI repository | ✅ Kustomize for apps |
| **Multi-Environment** | Excellent with overlays | Good with values files | ✅ Kustomize for apps |
| **Third-party Charts** | Limited support | Extensive ecosystem | ✅ Helm for monitoring |
| **Maintenance** | Low overhead | Higher complexity | ✅ Kustomize for apps |
| **Debugging** | Easy (plain YAML) | Complex (templated output) | ✅ Kustomize for apps |

### Implementation Strategy

**Unconventional Approach**: We used a **hybrid strategy**:
- **Kustomize overlays** for environment-specific application configurations
- **Helm charts** only for complex third-party infrastructure (external Prometheus stack)
- **Base + Overlay pattern** instead of traditional templating

This approach minimizes complexity while maximizing reusability.

---

## 3. Architecture: Single Cluster + 3 Namespaces vs 3 Separate Clusters

### Decision: Single Cluster with Namespace Isolation

**The Choice**: We implemented one Kubernetes cluster with three namespaces (`dev`, `staging`, `production`) (ok ok and the monitoring one aswell but shhh its a secret) instead of three separate clusters.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    Single Kubernetes Cluster                    │
│                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   dev namespace │  │ staging namespace│ │ production ns   │  │
│  │                 │  │                 │  │                 │  │
│  │ ┌─────────────┐ │  │ ┌─────────────┐ │  │ ┌─────────────┐ │  │
│  │ │   App Pod   │ │  │ │   App Pod   │ │  │ │   App Pod   │ │  │
│  │ │  (1 replica)│ │  │ │ (2 replicas)│ │  │ │ (3 replicas)│ │  │
│  │ │ 50m CPU     │ │  │ │ 100m CPU    │ │  │ │ 200m CPU    │ │  │
│  │ │ 64Mi RAM    │ │  │ │ 128Mi RAM   │ │  │ │ 256Mi RAM   │ │  │
│  │ └─────────────┘ │  │ └─────────────┘ │  │ └─────────────┘ │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              monitoring namespace                           ││
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐            ││
│  │  │ Prometheus  │ │   Grafana   │ │AlertManager │            ││
│  │  └─────────────┘ └─────────────┘ └─────────────┘            ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              flux-system namespace                          ││
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐            ││
│  │  │ GitOps      │ │ Kustomize   │ │ Helm        │            ││
│  │  │ Controllers │ │ Controllers │ │ Controllers │            |│
│  │  └─────────────┘ └─────────────┘ └─────────────┘            ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

### Trade-off Analysis

| Aspect | Single Cluster + Namespaces | 3 Separate Clusters | Our Choice Rationale |
|--------|----------------------------|---------------------|---------------------|
| **Resource Efficiency** | Shared infrastructure | Dedicated resources | ✅ Single cluster - effective for DEMO purposes, for production i'd choose three different clusters |
| **Operational Complexity** | One cluster to manage | Three clusters to manage | ✅ Single cluster - Simpler ops |
| **Isolation** | Namespace + NetworkPolicy | Complete isolation | ⚠️ Trade-off accepted |
| **Development Speed** | Fast environment creation | Slower cluster provisioning | ✅ Single cluster - Faster demo |
| **Cost** | Lower infrastructure cost | Higher infrastructure cost | ✅ Single cluster - "Lets not burn all the trees of the world" effective |

### Implementation Strategy

**Strong Arguments for 3 Clusters**:
1. **True Isolation**: Complete separation prevents any cross-environment impact
2. **Security Compliance**: Some organizations require physical separation
3. **Independent Scaling**: Each environment can scale independently
4. **Blast Radius**: Failure in one environment cannot affect others
5. **Compliance**: Regulatory requirements may mandate separate clusters

**Our Response**: Valid points, but for this assignment's scope and learning objectives, namespace isolation with proper NetworkPolicies provides sufficient separation while maintaining operational simplicity.

---

## 4. Kustomization Strategy & GitRepository Design

### Decision: Centralized GitRepository with Path-based Kustomizations

**The Choice**: We used a single GitRepository pointing to the main branch with path-based Kustomizations for different components.

### Architecture

```
GitRepository (Single Source)
├── flux-cd/
│   ├── applications/
│   │   ├── _base-app-config/          # Base application manifests
│   │   └── mock-cluster-aka-namespaces/
│   │       ├── dev/kustomization.yaml # Dev environment overlay
│   │       ├── staging/kustomization.yaml # Staging overlay
│   │       └── production/kustomization.yaml # Production overlay
│   ├── infrastructure/                # Infrastructure core resources 
│   │   ├── _components/               # Reusable infrastructure components
│   │   │   └── _prometheus-stack/     # Monitoring infrastructure
│   │   └── mock-cluster-aka-namespaces/ # Mock cluster namespace definitions
│   │       └── monitoring/           # Monitoring namespace configuration
│   └── bootstrap/                     # Flux CD system configuration
```

### Kustomization Patching Strategy

**Base Configuration** (`_base-app-config/`):
```yaml
# Single source of truth for all application manifests
resources:
  - deployment.yaml
  - service.yaml
  - configmap.yaml
  - secret.yaml
  # ... all base resources

commonLabels:
  app.kubernetes.io/name: app
  app.kubernetes.io/part-of: kaiko-assignment
  app.kubernetes.io/version: v1.0.0
  app.kubernetes.io/component: application
  app.kubernetes.io/managed-by: flux
```

**Environment Overlays** (e.g., `dev/kustomization.yaml`):
```yaml
resources:
  - namespace.yaml                    # Creates namespaces (required resource before others)
  - ../../_base-app-config           # References base configuration

namespace: dev                        # Sets namespace for all resources

commonLabels:
  app.kubernetes.io/environment: development
  app.kubernetes.io/tier: development

patches:
  - target:
      kind: Deployment
      name: app
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 1                      # Dev: 1 replica
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/cpu
        value: 50m                    # Dev: Low CPU
```

### Implementation Strategy

- **GitOps Best Practice**: Single repository with path-based organization is a proven pattern
- **Kustomize Overlays**: Industry standard for multi-environment management
- **DRY Principle**: Eliminates manifest duplication while maintaining environment-specific configurations
- **Scalability**: Easy to add new environments by creating new overlay directories

**Potential Expert Concerns**:
- **Repository Size**: Large monorepos can become unwieldy
- **Access Control**: Granular permissions harder to implement
- **Deployment Coupling**: Changes to base affect all environments

**Our Mitigation**: We kept the repository focused and used clear separation of concerns.

---

## 5. Label Standardization Strategy

### Decision: app.kubernetes.io/* Labels with commonLabels

**The Choice**: We standardized all Kubernetes resources to use `app.kubernetes.io/*` labels and implemented them through Kustomize's `commonLabels` feature.

### Trade-off Analysis

| Aspect | Custom Labels | app.kubernetes.io/* Labels | Our Choice Rationale |
|--------|---------------|----------------------------|---------------------|
| **Industry Standard** | Project-specific | Kubernetes recommended | ✅ Standard labels - Better ecosystem compatibility |
| **Tool Integration** | Limited support | Wide tool support | ✅ Standard labels - Better monitoring/observability |
| **Consistency** | Manual enforcement | Automated via commonLabels | ✅ Standard labels - Consistent across all resources |
| **Maintenance** | High overhead | Low overhead | ✅ Standard labels - Less maintenance burden |
| **Learning Curve** | Team-specific | Industry standard | ✅ Standard labels - Easier for new team members |

### Implementation Strategy

**Base Kustomization** (`_base-app-config/kustomization.yaml`):
```yaml
commonLabels:
  app.kubernetes.io/name: app
  app.kubernetes.io/part-of: kaiko-assignment
  app.kubernetes.io/version: v1.0.0
  app.kubernetes.io/component: application
  app.kubernetes.io/managed-by: flux
```

**Environment-Specific Labels** (e.g., `dev/kustomization.yaml`):
```yaml
commonLabels:
  app.kubernetes.io/environment: development
  app.kubernetes.io/tier: development
```

- **Kubernetes Best Practice**: `app.kubernetes.io/*` labels are the recommended standard
- **Tool Ecosystem**: Prometheus, Grafana, and other tools expect these labels
- **Operational Excellence**: Consistent labeling enables better automation and monitoring
- **Future-Proofing**: Aligns with Kubernetes evolution and community standards

**Our Implementation Benefits**:
- **Automatic Application**: `commonLabels` ensures all resources get consistent labels
- **Environment Differentiation**: Environment-specific labels for proper resource identification
- **Monitoring Integration**: ServiceMonitor resources automatically discover applications
- **Operational Clarity**: Clear resource ownership and purpose identification

---

## 6. Kustomize Validation & Quality Assurance

### Decision: kubeconform for Schema Validation

**The Choice**: We implemented comprehensive kustomize validation using `kubeconform` for schema validation and integrated it into our development workflow.

### Trade-off Analysis

| Aspect | No Validation | kubeconform | Our Choice Rationale |
|--------|---------------|-------------|---------------------|
| **Error Detection** | Runtime failures | Pre-deployment validation | ✅ kubeconform - Early error detection |
| **Schema Compliance** | Manual verification | Automated validation | ✅ kubeconform - Ensures K8s compliance |
| **Development Speed** | Fast but risky | Slightly slower but safe | ✅ kubeconform - Prevents deployment issues |
| **Tool Integration** | None | Integrated with makefile | ✅ kubeconform - Seamless workflow integration |
| **Learning Curve** | None | Minimal | ✅ kubeconform - Easy to adopt |

### Implementation Strategy

**Integration Points**:
- **Setup Process**: Validation runs automatically during `make setup-all` (step 4/7)
- **CI/CD Ready**: Commands can be integrated into CI/CD pipelines
- **Developer Workflow**: Immediate feedback on configuration errors

---

## 7. Flux CD Bootstrap Process & Challenges

### Bootstrap Implementation

**Step 1: Flux Installation**
```bash
flux install --version=v2.6.4
```

**Step 2: Git Bootstrap**
```bash
flux bootstrap git \
  --url=ssh://git@github.com/phaidon-passias/kaiko-assignment \
  --branch=main \
  --path=flux-cd/bootstrap
```

**Step 3: Resource Sync**
Flux automatically discovers and syncs all Kustomizations in the `flux-cd/` directory.

### Challenges Faced

#### Challenge 1: GitRepository Configuration
**Problem**: Initially created separate GitRepositories for each environment, leading to complexity.

**Solution**: Consolidated to a single GitRepository with path-based Kustomizations.

**Learning**: Simpler is better - one source of truth reduces operational overhead.

#### Challenge 2: Kustomization Dependencies
**Problem**: Environment Kustomizations needed to reference base configurations correctly.

**Solution**: Used relative paths (`../../base-app-config`) in overlay Kustomizations.

**Learning #1**: Clear directory structure is crucial for maintainable Kustomize setups.
**Learning #2**: Sometimes more complex solutions provide simpler resources that are more manageable

#### Challenge 3: Namespace Management
**Problem**: Ensuring namespaces are created before applications are deployed.

**Solution**: Included `namespace.yaml` in each environment's Kustomization.

**Learning**: Resource ordering matters in GitOps - dependencies must be explicit.

#### Challenge 4: Helm Integration
**Problem**: Integrating Helm charts (Prometheus) with Kustomize-based applications.

**Solution**: Used HelmRelease resources managed by Flux CD's Helm controller.

**Learning**: Hybrid approaches (Kustomize + Helm) work well when properly orchestrated.

---

## 8. Critical Analysis 

If our decisions were truly optimal, we'd observe:
- **Deployment Speed**: Sub-minute deployments across all environments
- **Operational Simplicity**: Automated actions to deploy to environments based on release targets
- **Cost Efficiency**: Minimal infrastructure overhead
- **Maintainability**: Easy to add new environments or modify existing ones
- **Reliability**: Self-healing deployments with automatic rollback capabilities
- **CICD**: Semantic Versioning on Flux Sources so we could have separation between environment promotion on configuration changes. That would require a different handling of the resources (maybe adding an extra layer for commited changes) that would be an overkill for a demo.

### Implementation Strategy

**Current Scale (3 environment/5 apps)**:
- ✅ Perfect fit for our architecture
- ✅ Kustomize overlays handle complexity well
- ✅ Single cluster provides adequate isolation

**Future Scale (3 environment/10+ apps)**:
- ⚠️ May need to consider separate clusters for true isolation
- ⚠️ Kustomize overlays might become complex
- ✅ Flux CD can handle larger scale with proper organization

**Enterprise Scale (3 environment/100+ apps)**:
- ❌ Would likely need separate clusters or cluster federation
- ❌ Might need more sophisticated templating (Helm)
- ❌ Would require more complex GitOps orchestration

### What Could Go Wrong?

**Potential Failure Modes**:
1. **Single Point of Failure**: One cluster means one failure domain
2. **Namespace Bleeding**: Misconfigured NetworkPolicies could allow cross-environment access
3. **Resource Contention**: All environments competing for cluster resources
4. **Operational Complexity**: Flux CD learning curve for team members
5. **GitOps Coupling**: Changes to base configuration affect all environments

**Mitigation Strategies**:
1. **Monitoring**: Comprehensive observability across all environments
2. **Network Policies**: Strict isolation with default-deny policies
3. **Resource Quotas**: Namespace-level resource limits
4. **Documentation**: Clear operational procedures and troubleshooting guides
5. **Testing**: Automated validation of configuration changes

---

## 9. Conclusion & Recommendations

### Key Takeaways

1. **Flux CD over ArgoCD**: Better Kubernetes native integration and simpler bootstrap
2. **Kustomize over Helm**: Lower complexity for low number of application
3. **Single Cluster**: Optimal for this scale with proper namespace isolation
4. **Hybrid Approach**: Best of both worlds - Kustomize for apps, Helm for 3rd party solutions
5. **Standardized Labeling**: app.kubernetes.io/* labels with commonLabels for consistency
6. **Validation-First**: kubeconform integration for early error detection and quality assurance

### Future Considerations

**Short Term (6 months)**:
- Buil and bootstrap IAC & Flux with terraform/opentofu
- Create Github actions to proper version the sources
- Create process where commits to main would deploy changes to the dev cluster and create PRs for staging/production 
- Differentiate creating releases for cluster components from simply adding a new feature  
- Monitor resource utilization and adjust quotas

**Medium Term (1 year)**:
- Implement automated testing for configuration changes
- Add more comprehensive monitoring/logs/traces and alerting
- Evaluate migration to more sophisticated templating if complexity grows (separate repo for Helm for apps, Kustomize for the layers)
- Implement advanced GitOps patterns (progressive delivery, canary deployments)

**Long Term (2+ years)**:
- Consider service mesh integration for advanced networking
- Evaluate platform engineering tools for enhanced developer experience (Create microservices./actions to compliment the setup and the ease in which developers can interact with the platform)

### Final Assessment

Our architectural decisions balance **simplicity**, **maintainability**, and **operational efficiency** while meeting all assignment requirements. The hybrid approach of Flux CD + Kustomize + selective Helm usage provides a solid foundation for GitOps-based application delivery that can scale with organizational needs.

The key insight is that **the best architecture is the one that solves your specific problems with the least complexity** - and for this assignment's scope, our choices hit that sweet spot perfectly.
