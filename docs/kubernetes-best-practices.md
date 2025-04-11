# Kubernetes Best Practices for Open edX Deployments

## Overview

This document outlines Kubernetes configuration best practices for Open edX deployments using the tutor-k3s project. These recommendations align with industry standards as of April 2025 and focus on security, performance, and reliability.

## Table of Contents

1. [Cluster Architecture](#cluster-architecture)
2. [Node Configuration](#node-configuration)
3. [Networking](#networking)
4. [Security](#security)
5. [Storage](#storage)
6. [Resource Management](#resource-management)
7. [High Availability](#high-availability)
8. [Backup and Disaster Recovery](#backup-and-disaster-recovery)

## Cluster Architecture

### Control Plane Configuration

For optimal reliability and performance, follow these control plane configurations based on deployment size:

| Deployment Size | Control Plane Configuration |
|-----------------|----------------------------|
| Testing/Development | 1 control plane node (4 vCPU, 8GB RAM) |
| Small Production | 3 control plane nodes (4 vCPU, 8GB RAM each) |
| Medium Production | 3 control plane nodes (4 vCPU, 8GB RAM each) |
| Large Production | 3 control plane nodes (8 vCPU, 16GB RAM each) |
| Enterprise | 5 control plane nodes (8 vCPU, 16GB RAM each) |

**Best Practices for All Production Deployments**:
- **Node distribution**: Place across different availability zones when possible
- **Dedicated nodes**: Keep control plane nodes dedicated (no workloads)
- **etcd considerations**: 
  - Use SSD storage for etcd (required for all tiers)
  - Allocate sufficient memory (8GB+) for larger clusters
  - Regular etcd backups (at least daily)

### Worker Node Topology

| Deployment Size | Worker Nodes | Purpose |
|-----------------|--------------|---------|
| Testing/Development (25-50 students) | 2 nodes | General purpose |
| Small Production (50-150 students) | 3 nodes | General purpose |
| Medium Production (150-500 students) | 5 nodes | Split between general and database-optimized |
| Large Production (500-1000 students) | 7-10 nodes | Specialized node groups by function |
| Enterprise (1000+ students) | 12+ nodes | Highly specialized node groups with auto-scaling |

### Node Labels and Taints

Organize your cluster with proper labels and taints:

```yaml
# Example node labels for specialized workloads
kubectl label nodes worker1 worker2 workload=general
kubectl label nodes worker3 worker4 workload=database
kubectl label nodes worker5 workload=frontend

# Example taints for dedicated database nodes
kubectl taint nodes worker3 worker4 dedicated=database:NoSchedule
```

## Node Configuration

### Recommended K3s Configuration

For Open edX deployments, configure K3s with these flags:

```bash
# Control plane setup
k3s server \
  --disable=traefik \     # We use NGINX Ingress instead
  --disable=servicelb \   # Use MetalLB or cloud provider LB
  --kube-apiserver-arg="default-not-ready-toleration-seconds=30" \
  --kube-apiserver-arg="default-unreachable-toleration-seconds=30" \
  --kube-controller-arg="node-monitor-period=20s" \
  --kube-controller-arg="node-monitor-grace-period=20s" \
  --kubelet-arg="max-pods=110" \
  --kubelet-arg="image-gc-high-threshold=85" \
  --kubelet-arg="image-gc-low-threshold=80"

# Worker node setup
k3s agent \
  --kubelet-arg="max-pods=110" \
  --kubelet-arg="system-reserved=cpu=200m,memory=512Mi" \
  --kubelet-arg="kube-reserved=cpu=200m,memory=512Mi"
```

### Container Runtime Settings

```bash
# Set Docker/containerd settings for larger images
cat > /etc/sysctl.d/99-kubernetes-inotify.conf << EOF
fs.inotify.max_user_instances=1024
fs.inotify.max_user_watches=1048576
EOF

# Apply changes
sysctl --system
```

## Networking

### Ingress Configuration

The NGINX Ingress Controller should be configured with these optimizations:

```yaml
# Custom NGINX ingress configuration for Open edX
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-configuration
  namespace: ingress-nginx
data:
  proxy-body-size: "100m"          # Allow larger uploads
  proxy-connect-timeout: "60s"     # Longer timeouts for video uploads
  proxy-read-timeout: "60s"
  proxy-send-timeout: "60s"
  client-max-body-size: "100m"
  enable-gzip: "true"
  gzip-types: "application/javascript application/x-javascript text/css text/javascript"
  use-gzip: "true"
  keep-alive: "75"                 # Keep connections alive longer
  worker-processes: "auto"
```

### Network Policies

Implement network policies to secure pod-to-pod communication:

```yaml
# Example network policy allowing only necessary OpenedX component communication
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: lms-policy
  namespace: openedx
spec:
  podSelector:
    matchLabels:
      app: lms
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    - podSelector:
        matchLabels:
          app: studio
    ports:
    - protocol: TCP
      port: 8000
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: mysql
    ports:
    - protocol: TCP
      port: 3306
  - to:
    - podSelector:
        matchLabels:
          app: mongodb
    ports:
    - protocol: TCP
      port: 27017
```

## Security

### Pod Security Standards

Apply appropriate Pod Security Standards:

```yaml
# Create namespace with security standards
apiVersion: v1
kind: Namespace
metadata:
  name: openedx
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### Secret Management

- Use Kubernetes secrets with proper RBAC
- Consider external secret management solutions for production (HashiCorp Vault, AWS Secrets Manager)
- Encrypt etcd data at rest
- Regularly rotate credentials

```bash
# Enable encryption for secrets at rest
cat > /etc/kubernetes/encryption-config.yaml << EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: $(head -c 32 /dev/urandom | base64)
      - identity: {}
EOF
```

## Storage

### Storage Classes

Configure appropriate storage classes for Open edX components:

```yaml
# Example storage class for database volumes
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: openedx-db-storage
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
```

### Persistent Volume Configuration

Create optimized persistent volumes for different components:

```yaml
# Example PVC for MySQL
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-data
  namespace: openedx
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
  storageClassName: openedx-db-storage
```

## Resource Management

### Resource Quotas by Deployment Size

Set appropriate namespace quotas based on your deployment size:

#### Testing/Development (25-50 Students)
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: openedx-quota-dev
  namespace: openedx
spec:
  hard:
    requests.cpu: "8"
    requests.memory: 16Gi
    limits.cpu: "16"
    limits.memory: 32Gi
    persistentvolumeclaims: "6"
```

#### Small Production (50-150 Students)
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: openedx-quota-small
  namespace: openedx
spec:
  hard:
    requests.cpu: "16"
    requests.memory: 32Gi
    limits.cpu: "24"
    limits.memory: 48Gi
    persistentvolumeclaims: "10"
```

#### Medium Production (150-500 Students)
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: openedx-quota-medium
  namespace: openedx
spec:
  hard:
    requests.cpu: "32"
    requests.memory: 64Gi
    limits.cpu: "48"
    limits.memory: 96Gi
    persistentvolumeclaims: "15"
```

#### Large Production (500+ Students)
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: openedx-quota-large
  namespace: openedx
spec:
  hard:
    requests.cpu: "64"
    requests.memory: 128Gi
    limits.cpu: "96"
    limits.memory: 192Gi
    persistentvolumeclaims: "25"
```

### Educational Content Requirements

Adjust resource allocations based on the type of educational content:

| Content Type | Resource Considerations |
|--------------|-------------------------|
| Mathematics courses | Additional CPU for formula rendering and computational exercises |
| Physics simulations | Higher memory requirements for interactive visualizations |
| Video lectures | Increased storage and memory for transcoding and streaming |
| Interactive labs | Dedicated compute resources with specialized storage |
| Real-time collaboration | Higher network bandwidth and lower latency requirements |

### LimitRanges

Set default limits for pods:

```yaml
# Default container limits
apiVersion: v1
kind: LimitRange
metadata:
  name: openedx-limits
  namespace: openedx
spec:
  limits:
  - default:
      memory: 512Mi
      cpu: 500m
    defaultRequest:
      memory: 256Mi
      cpu: 250m
    type: Container
```

## High Availability

### Pod Disruption Budgets

Ensure service continuity during node maintenance:

```yaml
# Example PDB for LMS service
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: lms-pdb
  namespace: openedx
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: lms
```

### Anti-affinity Rules

Distribute critical services across nodes:

```yaml
# Example deployment with anti-affinity
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lms
  namespace: openedx
spec:
  replicas: 3
  template:
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - lms
              topologyKey: "kubernetes.io/hostname"
```

## Backup and Disaster Recovery

### Regular Backup Strategy

| Component | Backup Frequency | Retention Period | Tool |
|-----------|------------------|------------------|------|
| MySQL data | Hourly | 7 days | Velero with restic |
| MongoDB data | Daily | 30 days | Velero with restic |
| Course content | Daily | 90 days | S3 versioning |
| etcd data | Daily | 14 days | etcdctl snapshot |
| Kubernetes manifests | On change | 90 days | GitOps (ArgoCD/Flux) |

### Example Velero Backup Configuration

```yaml
# Schedule daily backups
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: daily-openedx-backup
spec:
  schedule: "0 0 * * *"
  template:
    includedNamespaces:
    - openedx
    excludedResources:
    - endpoints
    includeClusterResources: true
    hooks:
      resources:
      - name: mysql-backup-hook
        includedNamespaces:
        - openedx
        labelSelector:
          matchLabels:
            app: mysql
        pre:
          exec:
            command:
            - /bin/bash
            - -c
            - "MYSQL_PWD=$MYSQL_ROOT_PASSWORD mysqldump -u root --all-databases > /backup/all-databases.sql"
    storageLocation: default
    volumeSnapshotLocations:
    - default
```

## Conclusion

Following these Kubernetes best practices will help ensure a secure, reliable, and performant Open edX deployment. Adapt these recommendations to your specific requirements and scale, and always test changes in a non-production environment first. Regular updates to Kubernetes, Open edX, and all components are essential for maintaining security and performance.
