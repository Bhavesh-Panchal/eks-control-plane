# AWS Resources Created by CloudFormation

This document lists all AWS resources created by the EKS CloudFormation deployment templates.

---

## Stack 1: VPC (01-vpc.yaml)

| Resource Type | Resource Name | Description |
|--------------|---------------|-------------|
| **EC2::VPC** | `{ClusterName}-vpc` | Virtual Private Cloud with configurable CIDR |
| **EC2::InternetGateway** | `{ClusterName}-igw` | Internet Gateway for public internet access |
| **EC2::VPCGatewayAttachment** | `{ClusterName}-igw-attachment` | Attaches IGW to VPC |
| **EC2::Subnet** | `{ClusterName}-public-1` | Public subnet in AZ 1 (for ALB/NLB) |
| **EC2::Subnet** | `{ClusterName}-public-2` | Public subnet in AZ 2 (for ALB/NLB) |
| **EC2::Subnet** | `{ClusterName}-public-3` | Public subnet in AZ 3 (for ALB/NLB) |
| **EC2::Subnet** | `{ClusterName}-private-1` | Private subnet in AZ 1 (for EKS nodes) |
| **EC2::Subnet** | `{ClusterName}-private-2` | Private subnet in AZ 2 (for EKS nodes) |
| **EC2::Subnet** | `{ClusterName}-private-3` | Private subnet in AZ 3 (for EKS nodes) |
| **EC2::NatGateway** | `{ClusterName}-natgw` | NAT Gateway for private subnet internet access |
| **EC2::EIP** | `{ClusterName}-natgw-eip` | Elastic IP for NAT Gateway |
| **EC2::RouteTable** | `{ClusterName}-public-rt` | Route table for public subnets (to IGW) |
| **EC2::RouteTable** | `{ClusterName}-private-rt-1` | Route table for private subnet 1 (to NAT) |
| **EC2::RouteTable** | `{ClusterName}-private-rt-2` | Route table for private subnet 2 (to NAT) |
| **EC2::RouteTable** | `{ClusterName}-private-rt-3` | Route table for private subnet 3 (to NAT) |
| **EC2::SubnetRouteTableAssociation** | (6 resources) | Associates route tables to subnets |
| **EC2::SecurityGroup** | `{ClusterName}-vpc-sg` | Security Group for EKS cluster |
| **EFS::FileSystem** | `{ClusterName}-efs` | EFS file system for shared storage |
| **EFS::MountTarget** | (3 resources) | EFS mount targets in each private subnet |

**Total Resources (Stack 1): ~28 resources**

---

## Stack 2: EKS Cluster (02-eks-cluster.yaml)

| Resource Type | Resource Name | Description |
|--------------|---------------|-------------|
| **IAM::Role** | `{ClusterName}-cluster-role` | IAM role for EKS cluster |
| **IAM::Policy** | (inline policy) | Cluster IAM policy |
| **EKS::Cluster** | `{ClusterName}` | Amazon EKS Cluster |
| **EKS::Addon** | `vpc-cni` | AWS VPC CNI plugin for pod networking |
| **EKS::Addon** | `kube-proxy` | Kubernetes network proxy |
| **EKS::Addon** | `eks-pod-identity-agent` | EKS Pod Identity Agent |
| **IAM::OpenIDConnectProvider** | (OIDC Provider) | OIDC provider for IRSA |
| **KMS::Key** | `{ClusterName}-key` | KMS encryption key for ENCRYPTION_CONFIG |
| **KMS::Alias** | `alias/{ClusterName}-key` | KMS key alias |
| **Lambda::Function** | `{ClusterName}-eks-version` | Lambda for EKS version lookup |
| **Lambda::Permission** | (invoke permission) | CloudFormation permission to invoke Lambda |
| **CloudWatch::LogsGroup** | `{ClusterName}-lambda-logs` | Lambda log group |
| **IAM::Role** | `{ClusterName}-lambda-role` | IAM role for Lambda function |
| **IAM::Policy** | (inline policy) | Lambda IAM policy |
| **EKS::PodIdentityAssociation** | `vpc-cni` | Pod Identity association for VPC CNI |
| **EKS::PodIdentityAssociation** | `kube-proxy` | Pod Identity association for kube-proxy |

**Total Resources (Stack 2): ~18 resources**

---

## Stack 3: Node Group (03-nodegroup.yaml)

| Resource Type | Resource Name | Description |
|--------------|---------------|-------------|
| **IAM::Role** | `{ClusterName}-nodegroup-role` | IAM role for EKS nodes |
| **IAM::Policy** | (inline policy) | Node group IAM policy (AmazonEKSWorkerNodePolicy, AmazonEC2ContainerRegistryReadOnly, AmazonEKS_CNI_Policy) |
| **EKS::Nodegroup** | `{ClusterName}-nodegroup` | EKS Managed Node Group with EC2 instances |

**Total Resources (Stack 3): ~4 resources**

---

## Stack 4: Addons (04-addons.yaml)

| Resource Type | Resource Name | Description |
|--------------|---------------|-------------|
| **EKS::Addon** | `coredns` | Kubernetes DNS service |
| **EKS::Addon** | `kube-proxy` | (if not in cluster) Kubernetes network proxy |
| **EKS::Addon** | `aws-ebs-csi-driver` | AWS EBS CSI driver for persistent storage |
| **EKS::Addon** | `aws-efs-csi-driver` | AWS EFS CSI driver for EFS storage |
| **EKS::Addon** | `amazon-cloudwatch-observability` | CloudWatch observability addon |
| **IAM::Role** | `{ClusterName}-ebs-csi-role` | IAM role for EBS CSI Pod Identity |
| **IAM::Policy** | (inline policy) | EBS CSI IAM policy |
| **EKS::PodIdentityAssociation** | `efs-csi-controller` | Pod Identity for EFS CSI controller |

**Total Resources (Stack 4): ~9 resources**

---

## Stack 5: Load Balancer Controller (05-load-balancer-controller.yaml)

| Resource Type | Resource Name | Description |
|--------------|---------------|-------------|
| **IAM::Role** | `{ClusterName}-lb-controller-role` | IAM role for Load Balancer Controller (IRSA) |
| **IAM::Policy** | `{ClusterName}-lb-controller-policy` | AWS Load Balancer Controller IAM policy |

**Note:** The AWS Load Balancer Controller is installed via Helm after the IAM role is created.

**Total Resources (Stack 5): ~3 resources (2 IAM + Helm chart)**

---

## Total Resource Count Summary

| Stack | Approximate Resources |
|-------|---------------------|
| Stack 1: VPC | 28 |
| Stack 2: EKS Cluster | 18 |
| Stack 3: Node Group | 4 |
| Stack 4: Addons | 9 |
| Stack 5: LB Controller | 3 |
| **Total** | **~62 resources** |

---

## Additional Created Resources (Not in CloudFormation)

### EC2 Instances (Auto-scaled by EKS)
- EC2 instances created by EKS Managed Node Group
- Count based on `NODE_DESIRED_CAPACITY` (default: 2)
- Instance type configurable via `INSTANCE_TYPE`

### Kubernetes Resources (via Helm/EKS Addons)
- Namespaces: `kube-system`, `invinsense` (if apps deployed)
- ServiceAccounts: `aws-load-balancer-controller`, `ebs-csi-controller-ssa`, `efs-csi-controller-sa`
- ConfigMaps, Deployments, DaemonSets, etc.

### Persistent Volume Claims (PVCs)
- EBS volumes created dynamically when PVCs are provisioned
- Tagged with `kubernetes.io/cluster/<cluster-name>=owned`

---

## Tagging Convention

All resources are tagged with the following tags for identification:

| Tag Key | Tag Value |
|---------|-----------|
| `Name` | `{ResourceName}` |
| `kubernetes.io/cluster/{ClusterName}` | `shared` (VPC resources) |
| `Environment` | `production` (default) |

---

## Cleanup Commands

### List All Cluster Resources

```bash
# CloudFormation stacks
aws cloudformation describe-stacks --region <region> \
  --query "Stacks[?contains(StackName, '<cluster-name>')].StackName" --output table

# EBS volumes (including Kubernetes-created)
aws ec2 describe-volumes --region <region> \
  --filters "Name=tag:kubernetes.io/cluster/<cluster-name>,Values=owned" \
  --query "Volumes[*].[VolumeId,Size,State]" --output table

# Helm releases
helm list -A

# EKS clusters
aws eks list-clusters --region <region>
```

### Force Delete All Resources

```bash
# Use the destroy script
./deploy.sh force-destroy

# Or manual cleanup
./deploy.sh destroy all  # Includes Helm + EBS cleanup
```
