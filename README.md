# AWS EKS CloudFormation Deployment

A production-ready, 4-stack CloudFormation deployment for Amazon EKS with optimized creation and deletion times.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         4-Stack Architecture                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Stack 1: VPC                    Stack 2: EKS Cluster               │
│  ┌─────────────────────┐         ┌─────────────────────┐            │
│  │ • VPC               │         │ • EKS Cluster       │            │
│  │ • 3 Public Subnets  │──────── │ • VPC CNI Addon     │            │
│  │ • 3 Private Subnets │         │ • Kube-Proxy Addon  │            │
│  │ • 1 NAT Gateway     │         │ • Pod Identity Addon│            │
│  │ • Route Tables      │         │ • OIDC Provider     │            │
│  │ • Internet Gateway  │         │ • KMS Key           │            │
│  └─────────────────────┘         └──────────┬──────────┘            │
│                                             │                       │
│                                             ▼                       │
│  Stack 4: Addons                 Stack 3: Node Group                │
│  ┌─────────────────────┐         ┌─────────────────────┐            │
│  │ • CoreDNS           │◀───────│ • Managed Node Group│            │
│  │ • Metrics Server    │         │ • IAM Role          │            │
│  │ • EBS CSI Driver    │         │ • AL2023 AMI        │            │
│  │ • Node Monitoring   │         │ • Auto Scaling      │            │
│  └─────────────────────┘         └─────────────────────┘            │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- AWS CLI configured with appropriate credentials
- kubectl installed
- Bash shell (Linux/macOS/WSL)

```bash
# Verify AWS credentials
aws sts get-caller-identity

# Verify kubectl
kubectl version --client
```

## Quick Start

### 1. Deploy Everything

```bash
cd cloudformation
chmod +x deploy.sh
./deploy.sh deploy all
```

You'll be prompted for:
- **Cluster Name**: Name for your EKS cluster (e.g., `prod-cluster`, `dev-eks`)
- **AWS Region**: Select from common regions or enter custom

### 2. Verify Deployment

```bash
# Check nodes
kubectl get nodes

# Check all pods
kubectl get pods -A

# Check addons
kubectl get daemonsets -n kube-system
```

### 3. Destroy Everything

```bash
./deploy.sh destroy all
```

The script automatically detects deployed clusters and shows a selection list:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                    DESTROY CONFIGURATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Searching for deployed EKS clusters...

  Found 2 deployed cluster(s):

    #   Cluster Name                Region
    ─────────────────────────────────────────────
    1)  prod-cluster                ap-south-1
    2)  dev-cluster                 us-east-1

  Select cluster to destroy [1-2]: 1
```

If no clusters are found:

```
Searching for deployed EKS clusters...

  No deployed EKS clusters found.

  Either:
    - No clusters have been deployed yet
    - Clusters were deployed in a different region
    - You don't have permission to list stacks
```

## Detailed Usage

### Available Commands

| Command | Description |
|---------|-------------|
| `deploy all` | Deploy all 4 stacks with interactive prompts |
| `deploy vpc` | Deploy VPC stack only |
| `deploy eks` | Deploy EKS cluster + non-node addons |
| `deploy nodegroup` | Deploy managed node group |
| `deploy addons` | Deploy node-dependent addons |
| `destroy all` | Fast parallel destroy all stacks |
| `destroy [stack]` | Destroy specific stack |
| `force-destroy` | Force delete stuck stacks |
| `status` | Show status of all stacks |
| `validate` | Validate all CloudFormation templates |
| `Devtron` | Run Devtron pre-requisite setup |

### Examples

```bash
# Interactive deployment
./deploy.sh deploy all

# Interactive destruction
./deploy.sh destroy all

# Check stack status
./deploy.sh status

# Validate templates before deployment
./deploy.sh validate

# Run Devtron pre-requisite setup
./deploy.sh Devtron

# Deploy individual stacks
./deploy.sh deploy vpc
./deploy.sh deploy eks
./deploy.sh deploy nodegroup
./deploy.sh deploy addons

# Destroy individual stacks (reverse order)
./deploy.sh destroy addons
./deploy.sh destroy nodegroup
./deploy.sh destroy eks
./deploy.sh destroy vpc

# Force delete stuck stacks
./deploy.sh force-destroy
```

### Non-Interactive Mode (CI/CD)

Skip prompts using environment variables:

```bash
# Deploy without prompts
CLUSTER_NAME=prod-cluster AWS_REGION=us-west-2 ./deploy.sh deploy all

# Destroy without prompts
CLUSTER_NAME=prod-cluster AWS_REGION=us-west-2 ./deploy.sh destroy all
```

## Stack Details

### Stack 1: VPC (`01-vpc.yaml`)

| Resource | Description |
|----------|-------------|
| VPC | 10.11.0.0/16 CIDR block |
| Public Subnets | 3 subnets across AZs |
| Private Subnets | 3 subnets across AZs |
| NAT Gateway | Single NAT for cost optimization |
| Route Tables | 1 public + 3 private |
| Internet Gateway | For public subnet access |

### Stack 2: EKS Cluster (`02-eks-cluster.yaml`)

| Resource | Description |
|----------|-------------|
| EKS Cluster | Latest Kubernetes version (auto-detected) |
| VPC CNI | Latest version with Pod Identity |
| Kube-Proxy | Latest version |
| Pod Identity Agent | For IAM role association |
| OIDC Provider | For IRSA support |
| KMS Key | Secrets encryption |

### Stack 3: Node Group (`03-nodegroup.yaml`)

| Resource | Description |
|----------|-------------|
| Managed Node Group | AL2023 x86_64 AMI |
| Instance Type | t3.large (configurable) |
| Scaling | Min: 2, Desired: 4, Max: 4 |
| Disk Size | 80 GB |

### Stack 4: Addons (`04-addons.yaml`)

| Addon | Description |
|-------|-------------|
| CoreDNS | Cluster DNS resolution |
| Metrics Server | Resource metrics for HPA/VPA |
| EBS CSI Driver | EBS volume provisioning (default StorageClass) |
| Node Monitoring Agent | Node health monitoring |

## Configuration

### Default Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| ClusterName | my-eks-cluster | Name prefix for all resources |
| AWS_REGION | us-east-1 | AWS region for deployment |
| InstanceType | t3.large | EC2 instance type for nodes |
| DesiredCapacity | 4 | Number of worker nodes |
| DiskSize | 80 | Node disk size in GB |

### Customizing Node Group

Edit `03-nodegroup.yaml` parameters:

```yaml
Parameters:
  InstanceType:
    Type: String
    Default: t3.large      # Change instance type
  DesiredCapacity:
    Type: Number
    Default: 4             # Change node count
  DiskSize:
    Type: Number
    Default: 80            # Change disk size
```

## Performance Optimizations

### Fast Deployment

- **Parallel Addon Creation**: Non-dependent addons deploy simultaneously
- **Latest Versions**: Lambda function auto-detects latest K8s and addon versions
- **Inline Pod Identity**: Associations embedded in addon resources
- **ResolveConflicts: NONE**: Faster addon installation

### Fast Deletion

- **Parallel Stack Deletion**: Addons + NodeGroup delete simultaneously
- **NAT Gateway Optimization**: `MaxDrainDurationSeconds: 30` (vs 350s default)
- **Force Delete Mode**: Handles stuck `DELETE_FAILED` stacks

### Estimated Times

| Operation | Time |
|-----------|------|
| Full Deploy | ~25-30 minutes |
| Full Destroy | ~10-12 minutes |
| VPC Only | ~2 minutes |
| EKS Cluster | ~15-20 minutes |
| Node Group | ~5-10 minutes |
| Addons | ~3-5 minutes |

## IAM Roles & Permissions

### Created IAM Roles

| Role | Purpose |
|------|---------|
| `{cluster}-cluster-role` | EKS control plane |
| `{cluster}-nodegroup-role` | EC2 worker nodes |
| `{cluster}-vpc-cni-pod-identity-role` | VPC CNI Pod Identity |
| `{cluster}-ebs-csi-pod-identity-role` | EBS CSI Pod Identity |
| `{cluster}-version-lookup-role` | Lambda for version detection |

### Node Group Policies

- AmazonEKSWorkerNodePolicy
- AmazonEKS_CNI_Policy
- AmazonEC2ContainerRegistryReadOnly
- AmazonSSMManagedInstanceCore

## Troubleshooting

### Stack Stuck in DELETE_FAILED

```bash
# Use force delete
./deploy.sh force-destroy
```

### Check Stack Events

```bash
# View CloudFormation events
aws cloudformation describe-stack-events \
  --stack-name my-eks-cluster-eks \
  --query 'StackEvents[0:10].[Timestamp,ResourceStatus,ResourceStatusReason]' \
  --output table
```

### View Stack Status

```bash
./deploy.sh status
```

### kubectl Not Configured

```bash
# Update kubeconfig
aws eks update-kubeconfig --region <region> --name <cluster-name>
```

### Addon Issues

```bash
# Check addon status
aws eks describe-addon --cluster-name <cluster-name> --addon-name vpc-cni

# List all addons
aws eks list-addons --cluster-name <cluster-name>
```

## File Structure

```
cloudformation/
├── README.md                 # This file
├── deploy.sh                 # Deployment script
├── 01-vpc.yaml              # Stack 1: VPC resources
├── 02-eks-cluster.yaml      # Stack 2: EKS cluster + non-node addons
├── 03-nodegroup.yaml        # Stack 3: Managed node group
└── 04-addons.yaml           # Stack 4: Node-dependent addons
```

## Post-Deployment

### Access the Cluster

```bash
# Configure kubectl (automatically done by deploy script)
aws eks update-kubeconfig --region <region> --name <cluster-name>

# Verify access
kubectl get nodes
kubectl get pods -A
```

### Deploy Sample Application

```bash
# Create a test deployment
kubectl create deployment nginx --image=nginx

# Expose it
kubectl expose deployment nginx --port=80 --type=LoadBalancer

# Check service
kubectl get svc nginx
```

### Use EBS Storage

The EBS CSI Driver is configured as default StorageClass:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  # Uses gp3 by default
```

## Clean Up

```bash
# Delete all resources
./deploy.sh destroy all

# Verify deletion
./deploy.sh status
```

## Support

For issues or questions:
1. Check CloudFormation stack events in AWS Console
2. Run `./deploy.sh status` to see current state
3. Review CloudWatch logs for Lambda/addon issues

