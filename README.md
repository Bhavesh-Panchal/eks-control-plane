# AWS EKS CloudFormation Deployment

Production-ready CloudFormation templates and automation for deploying Amazon EKS clusters with AWS Load Balancer Controller integration.

---

## Table of Contents

- [Quick Start](#quick-start)
- [Pre-Deployment Validation](#pre-deployment-validation)
- [Stack Architecture](#stack-architecture)
- [IAM Requirements](#iam-requirements)
- [Deployment Options](#deployment-options)
- [Cleanup Features](#cleanup-features)
- [Customization](#customization)
- [Troubleshooting](#troubleshooting)
- [Support](#support)

---

## Quick Start

### 1. Validate Permissions (Required First Step)

Before deploying, verify your AWS credentials have the required IAM permissions:

```bash
# Make validation script executable
chmod +x validate-permissions.sh

# Run validation
./validate-permissions.sh
```

**Expected Output:**
``╔══════════════════════════════════════════════════╗
║                   ✔ ALL PERMISSIONS OK                     ║
╚══════════════════════════════════════════════════╝

Total Permissions Checked: 116
Allowed: 116
Denied/Missing: 0
Pass Rate: 100%

```

If validation fails, see [IAM Requirements](#iam-requirements) below.

### 2. Deploy EKS Cluster

```bash
# Deploy all stacks
./deploy.sh deploy all
```

The script will prompt for:

- **Cluster Name**: Your EKS cluster identifier
- **AWS Region**: Target deployment region
- **VPC CIDR**: VPC network range (default: 10.11.0.0/16)
- **Node Architecture**: arm64 (Graviton) or x86_64
- **Node Configuration**: Instance type, scaling, disk size

### 3. Destroy Cluster

```bash
./deploy.sh destroy all
```

**Destroy Process (4 Phases):**

- **Phase 0:** Helm Chart Cleanup (lists all Helm releases, prompts for uninstall)
- **Phase 1:** Delete LB Controller + Addons + NodeGroup in parallel
- **Phase 2:** Delete EKS Cluster
- **Phase 3:** Delete VPC
- **Phase 4:** Cleanup EBS Volumes (finds Kubernetes-created volumes, prompts for deletion)

---

## Pre-Deployment Validation

### Why Validate First?

The `deploy.sh` script creates and manages multiple AWS resources. If permissions are missing, the deployment will fail partway through, leaving resources in an inconsistent state.

**Always run validation first** to ensure your IAM user/role has all required permissions.

### Validation Script Features

- ✅ Checks 116+ permissions across 8 AWS services
- ✅ Uses AWS IAM `simulate-principal-policy` API
- ✅ Works with AWS SSO and IAM roles
- ✅ Fast (~15 seconds)
- ✅ Clear pass/fail reporting with missing action list

### Running Validation

```bash
# Basic validation
./validate-permissions.sh

# Specify region
AWS_REGION=us-west-2 ./validate-permissions.sh
```

## Stack Architecture

### 5-Stack Deployment Model

```
┌─────────────────────────────────────────────────────────────────┐
│  Stack 1: VPC (01-vpc.yaml)                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ EC2: VPC, 6 Subnets, IGW, NAT Gateway, EIP,              │   │
│  │      4 Route Tables, Security Group                      │   │
│  │ EFS: FileSystem, 3 Mount Targets                         │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  Stack 2: EKS Cluster (02-eks-cluster.yaml)                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ IAM: Cluster Role, OIDC Provider, Pod Identity Role      │   │
│  │ KMS: Encryption Key                                     │   │
│  │ Lambda: Version Lookup Function                         │   │
│  │ EKS: Cluster, 3 Addons (vpc-cni, kube-proxy, pod-id)     │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  Stack 3: Node Group (03-nodegroup.yaml)                      │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ IAM: Node Group Role                                     │   │
│  │ EKS: Managed Node Group                                  │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  Stack 4: Addons (04-addons.yaml)                            │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ IAM: EBS CSI Pod Identity Role                           │   │
│  │ EKS: 5 Addons (coredns, metrics-server, ebs-csi,         │   │
│  │              efs-csi, node-monitoring)                    │   │
│  │ K8s: EFS StorageClass                                     │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  Stack 5: LB Controller (05-load-balancer-controller.yaml)      │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ IAM: Managed Policy, IRSA Role                           │   │
│  │ Helm: Install AWS Load Balancer Controller               │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Resource Summary

| Stack | Resources Created |
|--------|-------------------|
| **1. VPC** | VPC, 6 subnets (3 public, 3 private), Internet Gateway, NAT Gateway, Elastic IP, 4 Route Tables, EFS FileSystem, 3 EFS Mount Targets, Security Group |
| **2. EKS Cluster** | IAM roles (cluster, pod identity), KMS encryption key, Lambda function (version lookup), OIDC provider, EKS cluster, 3 EKS addons |
| **3. Node Group** | IAM role, EKS managed node group with EC2 instances |
| **4. Addons** | IAM role (EBS CSI pod identity), 5 EKS addons, EFS StorageClass |
| **5. LB Controller** | IAM managed policy, IAM role (IRSA), Helm chart installation |

---

## IAM Requirements

### Required Permissions

The deployment requires permissions across 8 AWS services (116+ actions total):

| Service | Key Permissions Required |
|---------|--------------------------|
| **CloudFormation** | CreateStack, UpdateStack, DeleteStack, DescribeStacks, etc. |
| **IAM** | CreateRole, DeleteRole, PassRole, CreatePolicy, CreateOpenIDConnectProvider, etc. |
| **EKS** | CreateCluster, CreateNodegroup, CreateAddon, etc. |
| **EC2** | CreateVpc, CreateSubnet, CreateNatGateway, AllocateAddress, CreateRouteTable, CreateSecurityGroup, etc. |
| **KMS** | CreateKey, PutKeyPolicy, etc. |
| **EFS** | CreateFileSystem, CreateMountTarget, etc. |
| **Lambda** | CreateFunction, InvokeFunction, etc. |
| **CloudWatch Logs** | CreateLogGroup, PutLogEvents, etc. |

### IAM Policy

The minimum required policy is available at:

```
iam-policies/eks-deployer-policy-minimal.json
```

### Attaching the Policy

**Option 1: Via AWS Console**

1. Go to IAM → Users → Your user
2. Click "Add permissions" → "Attach policies"
3. Search for and select `eks-deployer-policy-minimal.json`

**Option 2: Via AWS CLI**

```bash
# Create policy
aws iam create-policy \
  --policy-name EKS-Deployer-Minimal \
  --policy-document file://iam-policies/eks-deployer-policy-minimal.json

# Attach to your user
aws iam attach-user-policy \
  --user-name YOUR_USERNAME \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/EKS-Deployer-Minimal
```

### Permission Documentation

See [PERMISSIONS.md](PERMISSIONS.md) for detailed permission breakdown and explanations.

---

## Deployment Options

### Deploy All Stacks

```bash
./deploy.sh deploy all
```

### Deploy Specific Stacks

```bash
# Deploy VPC only
./deploy.sh deploy vpc

# Deploy VPC + EKS Cluster
./deploy.sh deploy eks

# Deploy VPC + EKS + Node Group
./deploy.sh deploy nodegroup

# Deploy through Addons
./deploy.sh deploy addons

# Deploy everything (5 stacks)
./deploy.sh deploy all
```

### Destroy Stacks

```bash
# Destroy Load Balancer Controller only
./deploy.sh destroy lb-controller

# Destroy Addons
./deploy.sh destroy addons

# Destroy Node Group
./deploy.sh destroy nodegroup

# Destroy EKS Cluster
./deploy.sh destroy eks

# Destroy VPC (must be last)
./deploy.sh destroy vpc

# FAST: Parallel destroy (LB + Addons + NodeGroup together)
./deploy.sh destroy all
```

### Stack Status

```bash
./deploy.sh status
```

---

## Cleanup Features

### Helm Chart Cleanup

During destroy, the script lists all installed Helm releases and prompts for cleanup:

```bash
./deploy.sh destroy all
```

**Interactive Options:**

- `all` - Uninstall ALL Helm releases (including custom apps)
- `deploy` - Uninstall only deploy.sh managed releases (aws-load-balancer-controller)
- `skip` - Skip Helm cleanup (manual cleanup required)

**Example Output:**

```
==> Found 3 Helm Release(s)

  Installed Helm Releases:
  ┌─────────────────────────────────────────────────────────────────┐
  │ NAME                       NAMESPACE       REVISION  UPDATED     │
  ├─────────────────────────────────────────────────────────────────┤
  │ aws-load-balancer...   kube-system     1         2025-01-15  │
  │ ingress-nginx          invinsense      2         2025-01-12  │
  │ cert-manager           invinsense      1         2025-01-12  │
  └─────────────────────────────────────────────────────────────────┘

  Uninstall Helm releases? [all/deploy/skip] [skip]:
```

### EBS Volume Cleanup

After all CloudFormation stacks are deleted, the script finds Kubernetes-created EBS volumes:

**Filters Applied:**

- Tag: `kubernetes.io/cluster/<cluster-name> = owned`
- Status: `available` (unattached volumes only)

**Example Output:**

```
==> Cleaning up EBS Volumes

  Found 2 unattached EBS volume(s):
  ┌─────────────────────────────────────────────────────────────────┐
  │ VOLUME ID           SIZE (GB)   PVC NAME                         │
  ├─────────────────────────────────────────────────────────────────┤
  │ vol-0abc123def456   10GB        pvc-data-mongodb-0              │
  │ vol-0def789ghi012   20GB        pvc-logs-app                    │
  └─────────────────────────────────────────────────────────────────┘

  Delete these volumes? [yes/no] [no]:
```

**Manual EBS Cleanup:**

```bash
# List cluster volumes
aws ec2 describe-volumes \
  --filters "Name=tag:kubernetes.io/cluster/<cluster-name>,Values=owned" \
  --query "Volumes[*].[VolumeId,Size,State]" \
  --output table

# Delete specific volume
aws ec2 delete-volume --volume-id vol-xxxxxxxx
```

---

## Customization

### Environment Variables

```bash
# Cluster configuration
export CLUSTER_NAME=my-eks-cluster
export AWS_REGION=us-west-2

# VPC configuration (for clients with existing CIDR ranges)
export VPC_CIDR=10.100.0.0/16           # Default: 10.11.0.0/16

# Node configuration
export NODE_ARCHITECTURE=arm64           # arm64 or x86_64
export INSTANCE_TYPE=c7g.2xlarge        # Graviton or Intel
export NODE_DISK_SIZE=80                # GB
export NODE_MIN_SIZE=2
export NODE_MAX_SIZE=4
export NODE_DESIRED_CAPACITY=2

# NodeGroup AZ distribution
export NODEGROUP_AZ_MODE=multi          # multi or single
export TARGET_AZ=us-west-2a             # for single AZ mode

# API Server IP restriction
export API_IP_RESTRICTION_ENABLED=true
export API_ALLOWED_CIDRS="1.2.3.4/32,5.6.7.8/32"
```

### VPC CIDR Configuration

Some clients may have existing network infrastructure that conflicts with the default VPC CIDR (`10.11.0.0/16`). You can customize the VPC CIDR block:

**Common Private CIDR Ranges:**

| CIDR Range | Usable IPs | Use Case |
|------------|------------|----------|
| `10.0.0.0/16` | 65,534 | General purpose |
| `10.11.0.0/16` | 65,534 | Default (as-is deployments) |
| `10.100.0.0/16` | 65,534 | Avoids conflicts with 10.0.x and 10.11.x |
| `172.16.0.0/16` | 65,534 | Corporate network avoidance |
| `172.20.0.0/16` | 65,534 | Corporate network avoidance |
| `192.168.0.0/16` | 65,534 | Home/office network avoidance |

**Deployment with custom CIDR:**

```bash
# Via environment variable (non-interactive)
VPC_CIDR=10.100.0.0/16 ./deploy.sh deploy all

# Or set and run interactively
export VPC_CIDR=172.20.0.0/16
./deploy.sh deploy all
```

**Note:** The VPC CIDR is automatically divided into 6 subnets (3 public, 3 private) using /20 prefixes (4,094 IPs each).

### Addon Resource Configuration

EFS CSI driver pods have resource limits configured:

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|-------------|----------|----------------|--------------|
| Controller | 25m | 100m | 64Mi | 128Mi |
| Node | 25m | 100m | 64Mi | 128Mi |

To customize, edit `04-addons.yaml` and modify the `ConfigurationValues` property.

---

## File Structure

```
cloudformation/
├── 01-vpc.yaml                      # VPC and networking
├── 02-eks-cluster.yaml               # EKS cluster + core addons
├── 03-nodegroup.yaml                 # Managed node group
├── 04-addons.yaml                   # Node-dependent addons
├── 05-load-balancer-controller.yaml # Load Balancer Controller
├── deploy.sh                         # Main deployment script
├── validate-permissions.sh           # Permission validation script
├── iam-policies/
│   ├── eks-deployer-policy-minimal.json  # Required IAM policy
│   └── eks-deployer-policy-complete.json   # Complete policy reference
├── RESOURCES.md                       # Complete AWS resources inventory
└── README.md                         # This file
```

**See [RESOURCES.md](RESOURCES.md)** for a complete list of all AWS resources created by the CloudFormation templates (~62 resources).

---

## Troubleshooting

### Validation Fails

**Problem:** Missing permissions error

**Solution:**

1. Check which permissions are missing from the validation output
2. Attach the `eks-deployer-policy-minimal.json` policy to your IAM user
3. Wait 30-60 seconds for IAM propagation
4. Re-run validation

### Deployment Fails

**Check CloudFormation events:**

```bash
aws cloudformation describe-stack-events \
  --stack-name <stack-name> \
  --region <region> \
  --query 'sort_by(StackEventTimestamp, DESC)[0:5]'
```

**Check EKS cluster status:**

```bash
aws eks describe-cluster \
  --name <cluster-name> \
  --region <region>
```

### Node Group Issues

**Check node group status:**

```bash
aws eks describe-nodegroup \
  --cluster-name <cluster-name> \
  --nodegroup-name <nodegroup-name> \
  --region <region>
```

**Check nodes:**

```bash
kubectl get nodes
kubectl get pods -A
```

### Addon Issues

**List addons:**

```bash
aws eks list-addons --cluster-name <cluster-name> --region <region>
```

**Check addon logs:**

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=<addon-name>
```

---

## Support

### Documentation

- [EKS Documentation](https://docs.aws.amazon.com/eks/)
- [CloudFormation Documentation](https://docs.aws.amazon.com/cloudformation/)
- [AWS Load Balancer Controller](https://github.com/kubernetes-sigs/aws-load-balancer-controller)

### Useful Commands

```bash
# Get kubeconfig for cluster
aws eks update-kubeconfig --region <region> --name <cluster-name>

# List EKS clusters
aws eks list-clusters --region <region>

# Describe stack
aws cloudformation describe-stacks --stack-name <stack-name> --region <region>

# Tail CloudFormation events
aws cloudformation describe-stack-events \
  --stack-name <stack-name> \
  --region <region> \
  --query 'sort_by(StackEventTimestamp, DESC)' \
  --output text
```
