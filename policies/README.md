# IAM Policies

IAM policies required for deploying and managing AWS EKS clusters via CloudFormation.

## Policy Files

| Policy | Purpose | Usage |
|--------|---------|-------|
| [eks-deployer-policy.json](eks-deployer-policy.json) | Permissions for EKS deployment | Attach to IAM user/role |
| [eks-deployer-trust-policy.json](eks-deployer-trust-policy.json) | Trust policy for assuming role | IAM role trust relationship |

## Policy Overview

### eks-deployer-policy.json

Comprehensive IAM policy granting permissions to:

**CloudFormation Operations**
- Create, update, delete stacks
- Describe stack resources and events

**EKS Cluster Management**
- Create and manage EKS clusters
- Configure cluster addons
- Manage node groups

**VPC and Networking**
- Create VPCs, subnets, route tables
- Configure NAT gateways and internet gateways
- Manage security groups and network ACLs

**IAM Role Management**
- Create IAM roles for EKS
- Attach policies to roles
- Manage OIDC providers

**EC2 and Auto Scaling**
- Launch EC2 instances
- Create auto-scaling groups
- Manage launch templates

**EFS File Systems**
- Create EFS file systems
- Configure mount targets

**KMS Encryption**
- Create KMS keys
- Manage key policies

**Lambda Functions**
- Create Lambda functions for custom resources
- Manage execution roles

## Setup

### Create IAM User for Deployment

```bash
# Create IAM user
aws iam create-user --user-name eks-deployer

# Attach policy
aws iam put-user-policy \
  --user-name eks-deployer \
  --policy-name EKSDeployerPolicy \
  --policy-document file://eks-deployer-policy.json

# Create access key
aws iam create-access-key --user-name eks-deployer
```

### Create IAM Role for Deployment

```bash
# Create role with trust policy
aws iam create-role \
  --role-name eks-deployer-role \
  --assume-role-policy-document file://eks-deployer-trust-policy.json

# Attach inline policy
aws iam put-role-policy \
  --role-name eks-deployer-role \
  --policy-name EKSDeployerPolicy \
  --policy-document file://eks-deployer-policy.json
```

### Assume Role (if using IAM role)

```bash
# Get temporary credentials
aws sts assume-role \
  --role-arn arn:aws:iam::ACCOUNT-ID:role/eks-deployer-role \
  --role-session-name eks-deployment-session

# Configure AWS CLI with temporary credentials
export AWS_ACCESS_KEY_ID="<AccessKeyId>"
export AWS_SECRET_ACCESS_KEY="<SecretAccessKey>"
export AWS_SESSION_TOKEN="<SessionToken>"
```

## Security Best Practices

### 1. Principle of Least Privilege

Review and remove unnecessary permissions:

```json
{
  "Effect": "Allow",
  "Action": [
    "eks:CreateCluster",
    "eks:DescribeCluster"
  ],
  "Resource": "arn:aws:eks:*:*:cluster/my-cluster-*"
}
```

### 2. Resource Restrictions

Limit actions to specific resources:

```json
{
  "Effect": "Allow",
  "Action": "ec2:*",
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "ec2:ResourceTag/Project": "EKS-Deployment"
    }
  }
}
```

### 3. MFA Requirement

Require MFA for sensitive operations:

```json
{
  "Effect": "Allow",
  "Action": [
    "eks:DeleteCluster",
    "cloudformation:DeleteStack"
  ],
  "Resource": "*",
  "Condition": {
    "Bool": {
      "aws:MultiFactorAuthPresent": "true"
    }
  }
}
```

### 4. IP Restrictions

Limit access from specific IP ranges:

```json
{
  "Effect": "Allow",
  "Action": "*",
  "Resource": "*",
  "Condition": {
    "IpAddress": {
      "aws:SourceIp": [
        "203.0.113.0/24",
        "198.51.100.0/24"
      ]
    }
  }
}
```

### 5. Time-based Access

Restrict deployment to specific time windows:

```json
{
  "Effect": "Allow",
  "Action": "cloudformation:CreateStack",
  "Resource": "*",
  "Condition": {
    "DateGreaterThan": {"aws:CurrentTime": "2024-01-01T00:00:00Z"},
    "DateLessThan": {"aws:CurrentTime": "2024-12-31T23:59:59Z"}
  }
}
```

## Permission Breakdown

### Minimum Required Permissions

For basic EKS deployment:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudformation:*",
        "eks:*",
        "ec2:*",
        "iam:CreateRole",
        "iam:AttachRolePolicy",
        "iam:PassRole"
      ],
      "Resource": "*"
    }
  ]
}
```

### Additional Permissions for Features

**EFS Support:**
```json
{
  "Effect": "Allow",
  "Action": [
    "elasticfilesystem:CreateFileSystem",
    "elasticfilesystem:CreateMountTarget",
    "elasticfilesystem:DescribeFileSystems"
  ],
  "Resource": "*"
}
```

**Load Balancer Controller:**
```json
{
  "Effect": "Allow",
  "Action": [
    "elasticloadbalancing:*",
    "ec2:DescribeAccountAttributes",
    "ec2:DescribeAddresses"
  ],
  "Resource": "*"
}
```

**KMS Encryption:**
```json
{
  "Effect": "Allow",
  "Action": [
    "kms:CreateKey",
    "kms:CreateAlias",
    "kms:DescribeKey"
  ],
  "Resource": "*"
}
```

## Validation

### Check Policy Syntax

```bash
# Validate JSON syntax
python -m json.tool eks-deployer-policy.json

# AWS CLI validation
aws iam validate-policy \
  --policy-document file://eks-deployer-policy.json
```

### Test Permissions

```bash
# Test CloudFormation access
aws cloudformation list-stacks

# Test EKS access
aws eks list-clusters

# Test EC2 access
aws ec2 describe-vpcs
```

### Policy Simulator

Use AWS Policy Simulator to test permissions:

```bash
# Install policy simulator CLI
pip install awscli-plugin-policy-simulator

# Test EKS create cluster permission
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::ACCOUNT-ID:user/eks-deployer \
  --action-names eks:CreateCluster
```

## Troubleshooting

### Access Denied Errors

1. Check policy attachment:
```bash
aws iam list-user-policies --user-name eks-deployer
aws iam list-attached-user-policies --user-name eks-deployer
```

2. Verify policy document:
```bash
aws iam get-user-policy \
  --user-name eks-deployer \
  --policy-name EKSDeployerPolicy
```

3. Check CloudTrail for denied actions:
```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AccessDenied \
  --max-results 10
```

### Common Issues

**PassRole Error**
- Ensure IAM policy includes `iam:PassRole` permission
- Verify trust relationship for assumed roles

**Resource Tag Condition**
- Check if resources have required tags
- Verify condition keys in policy

**MFA Not Present**
- Enable MFA on IAM user/role
- Re-authenticate with MFA

## Policy Updates

### Add New Permission

```bash
# Get current policy
aws iam get-user-policy \
  --user-name eks-deployer \
  --policy-name EKSDeployerPolicy > current-policy.json

# Edit and update
aws iam put-user-policy \
  --user-name eks-deployer \
  --policy-name EKSDeployerPolicy \
  --policy-document file://updated-policy.json
```

### Remove Permission

```bash
# Delete inline policy
aws iam delete-user-policy \
  --user-name eks-deployer \
  --policy-name EKSDeployerPolicy

# Attach managed policy instead
aws iam attach-user-policy \
  --user-name eks-deployer \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

## Cleanup

### Remove IAM User

```bash
# Delete access keys
aws iam list-access-keys --user-name eks-deployer
aws iam delete-access-key \
  --user-name eks-deployer \
  --access-key-id <AccessKeyId>

# Delete inline policies
aws iam delete-user-policy \
  --user-name eks-deployer \
  --policy-name EKSDeployerPolicy

# Delete user
aws iam delete-user --user-name eks-deployer
```

### Remove IAM Role

```bash
# Delete inline policies
aws iam delete-role-policy \
  --role-name eks-deployer-role \
  --policy-name EKSDeployerPolicy

# Delete role
aws iam delete-role --role-name eks-deployer-role
```

## References

- [AWS IAM Policy Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies.html)
- [EKS IAM Requirements](https://docs.aws.amazon.com/eks/latest/userguide/security-iam.html)
- [CloudFormation Service Role](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-iam-servicerole.html)
- [AWS Policy Generator](https://awspolicygen.s3.amazonaws.com/policygen.html)
