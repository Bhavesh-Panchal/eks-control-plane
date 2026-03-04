#!/bin/bash

#########################################################################
# EKS CloudFormation Deploy - FAST Permission Validation
#
# Uses batched simulate-principal-policy for faster results.
# 115 permissions checked in ~10-15 seconds instead of 60+ seconds.
#
# Usage:
#   ./validate-permissions.sh
#   AWS_REGION=us-west-2 ./validate-permissions.sh
#########################################################################

#############################################
# COLORS
#############################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

CHECK="✔"
CROSS="✘"

#############################################
# CONFIGURATION
#############################################
AWS_REGION="${AWS_REGION:-us-east-1}"

# Counters
TOTAL=0
PASSED=0
FAILED=0
declare -a MISSING_PERMS=()

#############################################
# HELPERS
#############################################
print_header() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_section() {
    echo ""
    echo -e "${CYAN}▶${NC} $1"
}

ok() { echo -e "  ${GREEN}${CHECK}${NC} $1"; ((PASSED++)); ((TOTAL++)); }
fail() { echo -e "  ${RED}${CROSS}${NC} $1"; ((FAILED++)); ((TOTAL++)); MISSING_PERMS+=("$1"); }

# Convert assumed-role ARN to role ARN
get_role_arn() {
    local arn="$1"
    if [[ "$arn" == *":assumed-role/"* ]]; then
        local account=$(echo "$arn" | cut -d':' -f5)
        local role="${arn#*assumed-role/}"
        local role_name="${role%%/*}"
        echo "arn:aws:iam::${account}:role/${role_name}"
    else
        echo "$arn"
    fi
}

# Check batch of permissions in ONE API call
check_batch() {
    local title="$1"
    local role_arn="$2"
    shift 2
    local perms=("$@")

    print_section "$title"

    # Call simulate-principal-policy with all actions at once
    local result
    result=$(aws iam simulate-principal-policy \
        --policy-source-arn "$role_arn" \
        --action-names "${perms[@]}" \
        --output json 2>/dev/null)

    if [ -z "$result" ]; then
        # API failed - mark all as failed
        for perm in "${perms[@]}"; do
            fail "$perm (API error)"
        done
        return
    fi

    # Process each result
    local count=$(echo "$result" | jq -r '.EvaluationResults | length' 2>/dev/null || echo "${#perms[@]}")

    for ((i=0; i<count; i++)); do
        local action=$(echo "$result" | jq -r ".EvaluationResults[$i].EvalActionName")
        local decision=$(echo "$result" | jq -r ".EvaluationResults[$i].EvalDecision")

        if [ "$decision" = "allowed" ]; then
            ok "$action"
        else
            fail "$action"
        fi
    done
}

#############################################
# MAIN
#############################################
main() {
    clear
    print_header "AWS EKS Deployment - Permission Validation"

    # Get identity
    echo -e "\n${YELLOW}Checking AWS Identity...${NC}"

    local identity
    identity=$(aws sts get-caller-identity --region "$AWS_REGION" --output json 2>/dev/null) || {
        echo -e "${RED}ERROR: Cannot authenticate${NC}"
        exit 2
    }

    local account arn userid
    account=$(echo "$identity" | jq -r '.Account')
    arn=$(echo "$identity" | jq -r '.Arn')
    userid=$(echo "$identity" | jq -r '.UserId')

    echo -e "  Account: ${GREEN}${account}${NC}"
    echo -e "  User:    ${GREEN}${userid}${NC}"
    echo -e "  Region:  ${GREEN}${AWS_REGION}${NC}"

    # Get role ARN for simulation
    local role_arn
    role_arn=$(get_role_arn "$arn")

    if [ "$role_arn" != "$arn" ]; then
        echo -e "  ${YELLOW}(Simulating as: ${role_arn})${NC}"
    fi

    echo -e "\n${YELLOW}Checking permissions (~15 seconds)...${NC}"

    #===========================================================
    # CHECK ALL PERMISSIONS IN BATCHES (faster!)
    #===========================================================

    check_batch "CloudFormation" "$role_arn" \
        "cloudformation:CreateStack" \
        "cloudformation:UpdateStack" \
        "cloudformation:DeleteStack" \
        "cloudformation:DescribeStacks" \
        "cloudformation:DescribeStackEvents" \
        "cloudformation:ListStacks" \
        "cloudformation:ValidateTemplate" \
        "cloudformation:GetTemplate" \
        "cloudformation:ListExports"

    check_batch "IAM - Roles & Policies" "$role_arn" \
        "iam:CreateRole" \
        "iam:DeleteRole" \
        "iam:GetRole" \
        "iam:PassRole" \
        "iam:UpdateAssumeRolePolicy" \
        "iam:TagRole" \
        "iam:ListRoles" \
        "iam:AttachRolePolicy" \
        "iam:DetachRolePolicy" \
        "iam:CreatePolicy" \
        "iam:DeletePolicy" \
        "iam:GetPolicy" \
        "iam:ListAttachedRolePolicies" \
        "iam:ListRolePolicies"

    check_batch "IAM - OIDC" "$role_arn" \
        "iam:CreateOpenIDConnectProvider" \
        "iam:DeleteOpenIDConnectProvider" \
        "iam:GetOpenIDConnectProvider" \
        "iam:ListOpenIDConnectProviders" \
        "iam:TagOpenIDConnectProvider"

    check_batch "EKS - Cluster" "$role_arn" \
        "eks:CreateCluster" \
        "eks:DeleteCluster" \
        "eks:DescribeCluster" \
        "eks:UpdateClusterConfig" \
        "eks:ListClusters" \
        "eks:TagResource"

    check_batch "EKS - Nodegroups & Addons" "$role_arn" \
        "eks:CreateNodegroup" \
        "eks:DeleteNodegroup" \
        "eks:DescribeNodegroup" \
        "eks:UpdateNodegroupConfig" \
        "eks:ListNodegroups" \
        "eks:CreateAddon" \
        "eks:DeleteAddon" \
        "eks:DescribeAddon" \
        "eks:UpdateAddon" \
        "eks:ListAddons" \
        "eks:DescribeAddonVersions" \
        "eks:CreatePodIdentityAssociation" \
        "eks:DeletePodIdentityAssociation"

    check_batch "EC2 - VPC & Subnets" "$role_arn" \
        "ec2:CreateVpc" \
        "ec2:DeleteVpc" \
        "ec2:DescribeVpcs" \
        "ec2:ModifyVpcAttribute" \
        "ec2:CreateTags" \
        "ec2:CreateSubnet" \
        "ec2:DeleteSubnet" \
        "ec2:DescribeSubnets" \
        "ec2:ModifySubnetAttribute"

    check_batch "EC2 - Networking" "$role_arn" \
        "ec2:CreateInternetGateway" \
        "ec2:DeleteInternetGateway" \
        "ec2:AttachInternetGateway" \
        "ec2:DetachInternetGateway" \
        "ec2:DescribeInternetGateways" \
        "ec2:CreateNatGateway" \
        "ec2:DeleteNatGateway" \
        "ec2:DescribeNatGateways" \
        "ec2:AllocateAddress" \
        "ec2:ReleaseAddress" \
        "ec2:DescribeAddresses"

    check_batch "EC2 - Routes & Security" "$role_arn" \
        "ec2:CreateRouteTable" \
        "ec2:DeleteRouteTable" \
        "ec2:DescribeRouteTables" \
        "ec2:CreateRoute" \
        "ec2:DeleteRoute" \
        "ec2:AssociateRouteTable" \
        "ec2:DisassociateRouteTable" \
        "ec2:CreateSecurityGroup" \
        "ec2:DeleteSecurityGroup" \
        "ec2:DescribeSecurityGroups" \
        "ec2:AuthorizeSecurityGroupIngress" \
        "ec2:RevokeSecurityGroupIngress"

    check_batch "EC2 - Describe Only" "$role_arn" \
        "ec2:DescribeAvailabilityZones" \
        "ec2:DescribeAccountAttributes" \
        "ec2:DescribeNetworkInterfaces" \
        "ec2:DescribeInstances" \
        "ec2:DescribeTags"

    check_batch "KMS" "$role_arn" \
        "kms:CreateKey" \
        "kms:DescribeKey" \
        "kms:EnableKeyRotation" \
        "kms:PutKeyPolicy" \
        "kms:TagResource" \
        "kms:ScheduleKeyDeletion" \
        "kms:CreateAlias" \
        "kms:DeleteAlias" \
        "kms:ListAliases"

    check_batch "EFS" "$role_arn" \
        "elasticfilesystem:CreateFileSystem" \
        "elasticfilesystem:DeleteFileSystem" \
        "elasticfilesystem:DescribeFileSystems" \
        "elasticfilesystem:CreateMountTarget" \
        "elasticfilesystem:DeleteMountTarget" \
        "elasticfilesystem:DescribeMountTargets" \
        "elasticfilesystem:TagResource"

    check_batch "Lambda & Logs" "$role_arn" \
        "lambda:CreateFunction" \
        "lambda:DeleteFunction" \
        "lambda:GetFunction" \
        "lambda:InvokeFunction" \
        "lambda:AddPermission" \
        "lambda:RemovePermission" \
        "logs:CreateLogGroup" \
        "logs:DeleteLogGroup" \
        "logs:DescribeLogGroups" \
        "logs:CreateLogStream" \
        "logs:PutLogEvents"

    check_batch "STS & ELB" "$role_arn" \
        "sts:GetCallerIdentity" \
        "iam:SimulatePrincipalPolicy" \
        "elasticloadbalancing:DescribeLoadBalancers" \
        "elasticloadbalancing:DescribeTargetGroups" \
        "elasticloadbalancing:DescribeListeners"

    #===========================================================
    # SUMMARY
    #===========================================================
    print_header "VALIDATION SUMMARY"

    echo ""
    printf "  Total Permissions Checked: ${CYAN}%d${NC}\n" "$TOTAL"
    printf "  ${GREEN}Allowed: %d${NC}\n" "$PASSED"
    printf "  ${RED}Denied/Missing: %d${NC}\n\n" "$FAILED"

    local pass_pct=0
    if [ "$TOTAL" -gt 0 ]; then
        pass_pct=$((PASSED * 100 / TOTAL))
    fi
    printf "  Pass Rate: ${pass_pct}%%\n\n"

    if [ "$FAILED" -eq 0 ]; then
        echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║                   ✔ ALL PERMISSIONS OK                     ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "  You can proceed with deployment:"
        echo "    ./deploy.sh deploy all"
        echo ""
        exit 0
    else
        echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║                   ✘ MISSING PERMISSIONS                    ║${NC}"
        echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "  Missing permissions (${FAILED}):"
        for p in "${MISSING_PERMS[@]}"; do
            echo "    • $p"
        done
        echo ""
        echo "  Contact your AWS administrator to add these permissions."
        echo "  Reference policy: iam-policies/eks-deployer-policy-minimal.json"
        echo ""
        exit 1
    fi
}

main "$@"
