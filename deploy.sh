#!/bin/bash
#############################################
# CloudFormation Sequential Deployment Script
# 4-Stack EKS Deployment
#############################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_step() {
    echo -e "\n${CYAN}==>${NC} ${GREEN}$1${NC}"
}

print_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

print_success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

# Default values
CLUSTER_NAME="${CLUSTER_NAME:-my-eks-cluster}"
AWS_REGION="${AWS_REGION:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTERACTIVE_MODE=false

# Check if env vars were explicitly set (for non-interactive mode)
ENV_CLUSTER_SET=false
ENV_REGION_SET=false
if [ -n "${CLUSTER_NAME+x}" ] && [ "$CLUSTER_NAME" != "my-eks-cluster" ]; then
    ENV_CLUSTER_SET=true
fi
if [ -n "${AWS_REGION+x}" ] && [ "$AWS_REGION" != "us-east-1" ]; then
    ENV_REGION_SET=true
fi

# Function to prompt for cluster name and region
prompt_for_config() {
    # Skip interactive prompts if both env vars are set
    if [ "$ENV_CLUSTER_SET" = true ] && [ "$ENV_REGION_SET" = true ]; then
        echo ""
        print_step "Using environment variables (non-interactive mode)"
        echo "  Cluster Name: $CLUSTER_NAME"
        echo "  AWS Region:   $AWS_REGION"
        update_stack_names
        return
    fi

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}                    DEPLOYMENT CONFIGURATION                      ${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Prompt for cluster name
    echo -e "${GREEN}Enter cluster/resource name${NC}"
    echo -e "  This name will be used for: VPC, EKS Cluster, Node Group, Addons"
    echo -e "  Example: my-eks-cluster, prod-cluster, dev-eks"
    echo ""
    read -p "  Cluster Name [${CLUSTER_NAME}]: " INPUT_NAME
    if [ -n "$INPUT_NAME" ]; then
        CLUSTER_NAME="$INPUT_NAME"
    fi
    echo ""

    # Prompt for region with common options
    echo -e "${GREEN}Select AWS Region${NC}"
    echo ""
    echo "  Common regions:"
    echo "    1) us-east-1      (N. Virginia)"
    echo "    2) us-east-2      (Ohio)"
    echo "    3) us-west-1      (N. California)"
    echo "    4) us-west-2      (Oregon)"
    echo "    5) eu-west-1      (Ireland)"
    echo "    6) eu-central-1   (Frankfurt)"
    echo "    7) ap-south-1     (Mumbai)"
    echo "    8) ap-southeast-1 (Singapore)"
    echo "    9) ap-northeast-1 (Tokyo)"
    echo "    0) Enter custom region"
    echo ""
    read -p "  Select region [1-9, 0 for custom, or press Enter for ${AWS_REGION}]: " REGION_CHOICE

    case $REGION_CHOICE in
        1) AWS_REGION="us-east-1" ;;
        2) AWS_REGION="us-east-2" ;;
        3) AWS_REGION="us-west-1" ;;
        4) AWS_REGION="us-west-2" ;;
        5) AWS_REGION="eu-west-1" ;;
        6) AWS_REGION="eu-central-1" ;;
        7) AWS_REGION="ap-south-1" ;;
        8) AWS_REGION="ap-southeast-1" ;;
        9) AWS_REGION="ap-northeast-1" ;;
        0)
            read -p "  Enter custom region: " CUSTOM_REGION
            if [ -n "$CUSTOM_REGION" ]; then
                AWS_REGION="$CUSTOM_REGION"
            fi
            ;;
        "") ;; # Keep default
        *)
            # If user typed a region name directly
            if [ -n "$REGION_CHOICE" ]; then
                AWS_REGION="$REGION_CHOICE"
            fi
            ;;
    esac

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Configuration Summary:${NC}"
    echo -e "    Cluster Name: ${YELLOW}${CLUSTER_NAME}${NC}"
    echo -e "    AWS Region:   ${YELLOW}${AWS_REGION}${NC}"
    echo ""
    echo -e "  Resources to be created:"
    echo -e "    • VPC:        ${CLUSTER_NAME}-vpc"
    echo -e "    • EKS:        ${CLUSTER_NAME}-eks"
    echo -e "    • NodeGroup:  ${CLUSTER_NAME}-nodegroup"
    echo -e "    • Addons:     ${CLUSTER_NAME}-addons"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    read -p "  Proceed with deployment? (y/n) [y]: " CONFIRM
    if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
        echo ""
        print_warning "Deployment cancelled by user."
        exit 0
    fi

    # Update stack names with new cluster name
    update_stack_names
    INTERACTIVE_MODE=true
}

# Function to update stack names after config
update_stack_names() {
    VPC_STACK="${CLUSTER_NAME}-vpc"
    EKS_STACK="${CLUSTER_NAME}-eks"
    NODEGROUP_STACK="${CLUSTER_NAME}-nodegroup"
    ADDONS_STACK="${CLUSTER_NAME}-addons"
}

# Function to find deployed EKS clusters across regions
find_deployed_clusters() {
    local clusters=()
    local regions=("us-east-1" "us-east-2" "us-west-1" "us-west-2" "eu-west-1" "eu-central-1" "ap-south-1" "ap-southeast-1" "ap-northeast-1")

    echo "  Scanning for deployed EKS clusters..."
    echo ""

    for region in "${regions[@]}"; do
        # Find EKS stacks in this region (stacks ending with -eks)
        local stacks=$(aws cloudformation list-stacks \
            --region "$region" \
            --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
            --query "StackSummaries[?ends_with(StackName, '-eks')].StackName" \
            --output text 2>/dev/null)

        if [ -n "$stacks" ]; then
            for stack in $stacks; do
                # Extract cluster name (remove -eks suffix)
                local cluster_name="${stack%-eks}"
                clusters+=("$cluster_name|$region")
            done
        fi
    done

    echo "${clusters[@]}"
}

# Function to prompt for cluster name and region for destroy operations
prompt_for_destroy_config() {
    # Skip interactive prompts if both env vars are set
    if [ "$ENV_CLUSTER_SET" = true ] && [ "$ENV_REGION_SET" = true ]; then
        echo ""
        print_step "Using environment variables (non-interactive mode)"
        echo "  Cluster Name: $CLUSTER_NAME"
        echo "  AWS Region:   $AWS_REGION"
        update_stack_names
        echo ""
        echo -e "${RED}  Stacks to be DESTROYED:${NC}"
        echo -e "    • ${ADDONS_STACK}"
        echo -e "    • ${NODEGROUP_STACK}"
        echo -e "    • ${EKS_STACK}"
        echo -e "    • ${VPC_STACK}"
        return
    fi

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}                    DESTROY CONFIGURATION                         ${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Find deployed clusters
    echo -e "${GREEN}Searching for deployed EKS clusters...${NC}"
    echo ""

    local cluster_list=()
    local regions=("us-east-1" "us-east-2" "us-west-1" "us-west-2" "eu-west-1" "eu-central-1" "ap-south-1" "ap-southeast-1" "ap-northeast-1")

    for region in "${regions[@]}"; do
        # Find EKS stacks in this region
        local stacks=$(aws cloudformation list-stacks \
            --region "$region" \
            --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE \
            --query "StackSummaries[?ends_with(StackName, '-eks')].StackName" \
            --output text 2>/dev/null)

        if [ -n "$stacks" ] && [ "$stacks" != "None" ]; then
            for stack in $stacks; do
                local cluster_name="${stack%-eks}"
                cluster_list+=("$cluster_name|$region")
            done
        fi
    done

    if [ ${#cluster_list[@]} -eq 0 ]; then
        echo -e "${YELLOW}  No deployed EKS clusters found.${NC}"
        echo ""
        echo "  Either:"
        echo "    - No clusters have been deployed yet"
        echo "    - Clusters were deployed in a different region"
        echo "    - You don't have permission to list stacks"
        echo ""
        exit 0
    else
        # Display found clusters
        echo -e "${GREEN}  Found ${#cluster_list[@]} deployed cluster(s):${NC}"
        echo ""
        echo -e "    ${CYAN}#   Cluster Name                Region${NC}"
        echo "    ─────────────────────────────────────────────"

        local i=1
        for cluster_info in "${cluster_list[@]}"; do
            local name="${cluster_info%|*}"
            local region="${cluster_info#*|}"
            printf "    ${YELLOW}%d)${NC}  %-27s %s\n" "$i" "$name" "$region"
            ((i++))
        done

        echo ""
        read -p "  Select cluster to destroy [1-${#cluster_list[@]}]: " CLUSTER_CHOICE

        if [[ "$CLUSTER_CHOICE" =~ ^[0-9]+$ ]] && [ "$CLUSTER_CHOICE" -ge 1 ] && [ "$CLUSTER_CHOICE" -le ${#cluster_list[@]} ]; then
            local selected="${cluster_list[$((CLUSTER_CHOICE-1))]}"
            CLUSTER_NAME="${selected%|*}"
            AWS_REGION="${selected#*|}"
        else
            print_error "Invalid selection"
            exit 1
        fi
    fi

    # Update stack names
    update_stack_names

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}  Stacks to be DESTROYED:${NC}"
    echo ""
    echo -e "    Cluster: ${YELLOW}${CLUSTER_NAME}${NC}"
    echo -e "    Region:  ${YELLOW}${AWS_REGION}${NC}"
    echo ""
    echo -e "    Stacks:"
    echo -e "      • ${ADDONS_STACK}"
    echo -e "      • ${NODEGROUP_STACK}"
    echo -e "      • ${EKS_STACK}"
    echo -e "      • ${VPC_STACK}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    read -p "  Are you sure you want to DESTROY these stacks? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo ""
        print_warning "Destroy cancelled. You must type 'yes' to confirm."
        exit 0
    fi
}

# Stack names (initial, may be updated by prompt_for_config)
VPC_STACK="${CLUSTER_NAME}-vpc"
EKS_STACK="${CLUSTER_NAME}-eks"
NODEGROUP_STACK="${CLUSTER_NAME}-nodegroup"
ADDONS_STACK="${CLUSTER_NAME}-addons"

echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║       AWS EKS CloudFormation 4-Stack Deployment                ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  Stack 1: VPC (subnets, NAT, routes)                           ║"
echo "║  Stack 2: EKS Cluster + Non-Node Addons                        ║"
echo "║  Stack 3: Node Group                                           ║"
echo "║  Stack 4: Node-Dependent Addons                                ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  FAST DESTROY: Stacks 3+4 deleted in PARALLEL                  ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

usage() {
    echo "Usage: $0 [command] [stack]"
    echo ""
    echo "Commands:"
    echo "  deploy [stack]    Deploy stack(s)"
    echo "  destroy [stack]   Destroy stack(s)"
    echo "  force-destroy     Force delete all stacks (for stuck DELETE_FAILED)"
    echo "  status            Show status of all stacks"
    echo "  validate          Validate all CloudFormation templates"
    echo "  Devtron        Run Devtron pre-requisite setup"
    echo ""
    echo "Stack Options:"
    echo "  vpc               Stack 1: VPC, subnets, NAT Gateway, route tables"
    echo "  eks               Stack 2: EKS Cluster + vpc-cni, kube-proxy, pod-identity"
    echo "  nodegroup         Stack 3: Managed Node Group"
    echo "  addons            Stack 4: coredns, metrics-server, ebs-csi, node-monitoring"
    echo "  all               All stacks in sequence"
    echo ""
    echo "Examples:"
    echo "  $0 deploy vpc        # Deploy VPC only"
    echo "  $0 deploy eks        # Deploy EKS cluster + non-node addons"
    echo "  $0 deploy nodegroup  # Deploy node group"
    echo "  $0 deploy addons     # Deploy node-dependent addons"
    echo "  $0 deploy all        # Deploy all 4 stacks sequentially"
    echo ""
    echo "  $0 destroy addons    # Destroy addons only"
    echo "  $0 destroy nodegroup # Destroy node group only"
    echo "  $0 destroy eks       # Destroy EKS cluster only"
    echo "  $0 destroy vpc       # Destroy VPC only"
    echo "  $0 destroy all       # FAST: Parallel destroy (Addons+NodeGroup together)"
    echo ""
    echo "  $0 force-destroy     # Force delete stuck stacks (DELETE_FAILED)"
    echo ""
    echo "  $0 status            # Show all stack status"
    echo "  $0 validate          # Validate all templates"
    echo "  $0 Devtron           # Pre-requisite-for Devtron"
    echo ""
    echo "Environment Variables (skip interactive prompts):"
    echo "  CLUSTER_NAME=my-cluster AWS_REGION=us-west-2 $0 deploy all"
    echo "  CLUSTER_NAME=my-cluster AWS_REGION=us-west-2 $0 destroy all"
    echo ""
    exit 1
}

wait_for_stack() {
    local stack_name=$1
    local operation=$2

    echo "  Waiting for $stack_name to $operation..."

    if [ "$operation" == "create" ]; then
        aws cloudformation wait stack-create-complete --stack-name "$stack_name" --region "$AWS_REGION"
    elif [ "$operation" == "delete" ]; then
        aws cloudformation wait stack-delete-complete --stack-name "$stack_name" --region "$AWS_REGION"
    elif [ "$operation" == "update" ]; then
        aws cloudformation wait stack-update-complete --stack-name "$stack_name" --region "$AWS_REGION"
    fi
}

# Fast parallel delete - starts deletion and returns immediately
start_delete_stack() {
    local stack_name=$1

    if ! stack_exists "$stack_name"; then
        echo "  Stack $stack_name does not exist. Skipping..."
        return 1
    fi

    echo "  Starting deletion of $stack_name..."
    aws cloudformation delete-stack --stack-name "$stack_name" --region "$AWS_REGION"
    return 0
}

# Wait for multiple stacks to finish deleting (parallel wait)
wait_for_stacks_delete() {
    local stacks=("$@")
    local pids=()

    for stack in "${stacks[@]}"; do
        if stack_exists "$stack" 2>/dev/null || \
           aws cloudformation describe-stacks --stack-name "$stack" --region "$AWS_REGION" 2>&1 | grep -q "DELETE_IN_PROGRESS"; then
            (
                aws cloudformation wait stack-delete-complete --stack-name "$stack" --region "$AWS_REGION" 2>/dev/null
            ) &
            pids+=($!)
            echo "  Waiting for $stack deletion (PID: $!)..."
        fi
    done

    # Wait for all background waits to complete
    for pid in "${pids[@]}"; do
        wait $pid 2>/dev/null
    done
}

# Force delete a stack that is stuck in DELETE_FAILED
force_delete_stack() {
    local stack_name=$1

    # Check if stack exists
    if ! aws cloudformation describe-stacks --stack-name "$stack_name" --region "$AWS_REGION" &> /dev/null; then
        echo "  Stack $stack_name does not exist. Skipping..."
        return 0
    fi

    local status=$(aws cloudformation describe-stacks --stack-name "$stack_name" --region "$AWS_REGION" \
        --query 'Stacks[0].StackStatus' --output text 2>/dev/null)

    echo "  Stack $stack_name status: $status"

    if [ "$status" == "DELETE_FAILED" ]; then
        echo "  Force deleting $stack_name (DELETE_FAILED state)..."
        aws cloudformation delete-stack \
            --stack-name "$stack_name" \
            --deletion-mode FORCE_DELETE_STACK \
            --region "$AWS_REGION"
    elif [ "$status" == "DELETE_IN_PROGRESS" ]; then
        echo "  Stack $stack_name is already being deleted. Waiting..."
    else
        echo "  Initiating deletion for $stack_name..."
        aws cloudformation delete-stack --stack-name "$stack_name" --region "$AWS_REGION"
    fi

    # Wait for deletion
    aws cloudformation wait stack-delete-complete --stack-name "$stack_name" --region "$AWS_REGION" 2>/dev/null
    return 0
}

stack_exists() {
    local stack_name=$1
    aws cloudformation describe-stacks --stack-name "$stack_name" --region "$AWS_REGION" &> /dev/null
    return $?
}

deploy_vpc() {
    print_step "Stack 1/4: Deploying VPC Stack: $VPC_STACK"

    if stack_exists "$VPC_STACK"; then
        print_warning "Stack $VPC_STACK already exists. Updating..."
        aws cloudformation update-stack \
            --stack-name "$VPC_STACK" \
            --template-body "file://${SCRIPT_DIR}/01-vpc.yaml" \
            --parameters \
                ParameterKey=ClusterName,ParameterValue="$CLUSTER_NAME" \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$AWS_REGION" 2>/dev/null || {
                echo "  No updates needed or update in progress"
                return 0
            }
        wait_for_stack "$VPC_STACK" "update"
    else
        aws cloudformation create-stack \
            --stack-name "$VPC_STACK" \
            --template-body "file://${SCRIPT_DIR}/01-vpc.yaml" \
            --parameters \
                ParameterKey=ClusterName,ParameterValue="$CLUSTER_NAME" \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$AWS_REGION"
        wait_for_stack "$VPC_STACK" "create"
    fi

    print_success "VPC Stack deployed successfully!"
}

deploy_eks() {
    print_step "Stack 2/4: Deploying EKS Cluster + Non-Node Addons: $EKS_STACK"

    # Verify VPC stack exists
    if ! stack_exists "$VPC_STACK"; then
        print_error "VPC stack ($VPC_STACK) must be deployed first!"
        echo "  Run: $0 deploy vpc"
        exit 1
    fi

    if stack_exists "$EKS_STACK"; then
        print_warning "Stack $EKS_STACK already exists. Updating..."
        aws cloudformation update-stack \
            --stack-name "$EKS_STACK" \
            --template-body "file://${SCRIPT_DIR}/02-eks-cluster.yaml" \
            --parameters \
                ParameterKey=ClusterName,ParameterValue="$CLUSTER_NAME" \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$AWS_REGION" 2>/dev/null || {
                echo "  No updates needed or update in progress"
                return 0
            }
        wait_for_stack "$EKS_STACK" "update"
    else
        echo "  Creating EKS Cluster with:"
        echo "    - vpc-cni addon"
        echo "    - kube-proxy addon"
        echo "    - eks-pod-identity-agent addon"
        echo "    - OIDC Provider for IRSA"
        echo ""
        echo "  This will take approximately 15-20 minutes..."

        aws cloudformation create-stack \
            --stack-name "$EKS_STACK" \
            --template-body "file://${SCRIPT_DIR}/02-eks-cluster.yaml" \
            --parameters \
                ParameterKey=ClusterName,ParameterValue="$CLUSTER_NAME" \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$AWS_REGION"

        wait_for_stack "$EKS_STACK" "create"
    fi

    print_success "EKS Cluster + Non-Node Addons deployed successfully!"

    # Configure kubectl
    print_step "Configuring kubectl..."
    aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
    echo "  kubectl configured for cluster: $CLUSTER_NAME"
}

deploy_nodegroup() {
    print_step "Stack 3/4: Deploying Node Group: $NODEGROUP_STACK"

    # Verify EKS stack exists
    if ! stack_exists "$EKS_STACK"; then
        print_error "EKS stack ($EKS_STACK) must be deployed first!"
        echo "  Run: $0 deploy eks"
        exit 1
    fi

    if stack_exists "$NODEGROUP_STACK"; then
        print_warning "Stack $NODEGROUP_STACK already exists. Updating..."
        aws cloudformation update-stack \
            --stack-name "$NODEGROUP_STACK" \
            --template-body "file://${SCRIPT_DIR}/03-nodegroup.yaml" \
            --parameters \
                ParameterKey=ClusterName,ParameterValue="$CLUSTER_NAME" \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$AWS_REGION" 2>/dev/null || {
                echo "  No updates needed or update in progress"
                return 0
            }
        wait_for_stack "$NODEGROUP_STACK" "update"
    else
        echo "  Creating Managed Node Group..."
        echo "  This will take approximately 5-10 minutes..."

        aws cloudformation create-stack \
            --stack-name "$NODEGROUP_STACK" \
            --template-body "file://${SCRIPT_DIR}/03-nodegroup.yaml" \
            --parameters \
                ParameterKey=ClusterName,ParameterValue="$CLUSTER_NAME" \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$AWS_REGION"

        wait_for_stack "$NODEGROUP_STACK" "create"
    fi

    print_success "Node Group deployed successfully!"

    # Show nodes
    echo ""
    echo "  Verifying nodes..."
    kubectl get nodes
}

deploy_addons() {
    print_step "Stack 4/4: Deploying Node-Dependent Addons: $ADDONS_STACK"

    # Verify Node Group stack exists
    if ! stack_exists "$NODEGROUP_STACK"; then
        print_error "Node Group stack ($NODEGROUP_STACK) must be deployed first!"
        echo "  Run: $0 deploy nodegroup"
        exit 1
    fi

    # Wait for nodes to be ready
    echo "  Waiting for nodes to be ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=300s

    if stack_exists "$ADDONS_STACK"; then
        print_warning "Stack $ADDONS_STACK already exists. Updating..."
        aws cloudformation update-stack \
            --stack-name "$ADDONS_STACK" \
            --template-body "file://${SCRIPT_DIR}/04-addons.yaml" \
            --parameters \
                ParameterKey=ClusterName,ParameterValue="$CLUSTER_NAME" \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$AWS_REGION" 2>/dev/null || {
                echo "  No updates needed or update in progress"
                return 0
            }
        wait_for_stack "$ADDONS_STACK" "update"
    else
        echo "  Installing node-dependent addons:"
        echo "    - coredns"
        echo "    - metrics-server"
        echo "    - aws-ebs-csi-driver"
        echo "    - Node monitoring agent"
        echo ""

        aws cloudformation create-stack \
            --stack-name "$ADDONS_STACK" \
            --template-body "file://${SCRIPT_DIR}/04-addons.yaml" \
            --parameters \
                ParameterKey=ClusterName,ParameterValue="$CLUSTER_NAME" \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$AWS_REGION"

        wait_for_stack "$ADDONS_STACK" "create"
    fi

    print_success "Node-Dependent Addons deployed successfully!"
}

destroy_vpc() {
    print_step "Destroying VPC Stack: $VPC_STACK"

    if ! stack_exists "$VPC_STACK"; then
        print_warning "Stack $VPC_STACK does not exist. Skipping..."
        return 0
    fi

    # Check if dependent stacks exist
    if stack_exists "$EKS_STACK"; then
        print_error "EKS stack ($EKS_STACK) must be destroyed first!"
        echo "  Run: $0 destroy eks"
        exit 1
    fi

    aws cloudformation delete-stack --stack-name "$VPC_STACK" --region "$AWS_REGION"
    wait_for_stack "$VPC_STACK" "delete"

    print_success "VPC Stack destroyed successfully!"
}

destroy_eks() {
    print_step "Destroying EKS Stack: $EKS_STACK"

    if ! stack_exists "$EKS_STACK"; then
        print_warning "Stack $EKS_STACK does not exist. Skipping..."
        return 0
    fi

    # Check if dependent stacks exist
    if stack_exists "$NODEGROUP_STACK"; then
        print_error "Node group stack ($NODEGROUP_STACK) must be destroyed first!"
        echo "  Run: $0 destroy nodegroup"
        exit 1
    fi

    aws cloudformation delete-stack --stack-name "$EKS_STACK" --region "$AWS_REGION"
    echo "  This will take approximately 10-15 minutes..."
    wait_for_stack "$EKS_STACK" "delete"

    print_success "EKS Stack destroyed successfully!"
}

destroy_nodegroup() {
    print_step "Destroying Node Group Stack: $NODEGROUP_STACK"

    if ! stack_exists "$NODEGROUP_STACK"; then
        print_warning "Stack $NODEGROUP_STACK does not exist. Skipping..."
        return 0
    fi

    # Check if dependent stacks exist
    if stack_exists "$ADDONS_STACK"; then
        print_error "Addons stack ($ADDONS_STACK) must be destroyed first!"
        echo "  Run: $0 destroy addons"
        exit 1
    fi

    aws cloudformation delete-stack --stack-name "$NODEGROUP_STACK" --region "$AWS_REGION"
    wait_for_stack "$NODEGROUP_STACK" "delete"

    print_success "Node Group Stack destroyed successfully!"
}

destroy_addons() {
    print_step "Destroying Addons Stack: $ADDONS_STACK"

    if ! stack_exists "$ADDONS_STACK"; then
        print_warning "Stack $ADDONS_STACK does not exist. Skipping..."
        return 0
    fi

    aws cloudformation delete-stack --stack-name "$ADDONS_STACK" --region "$AWS_REGION"
    wait_for_stack "$ADDONS_STACK" "delete"

    print_success "Addons Stack destroyed successfully!"
}

show_status() {
    print_step "Stack Status"
    echo ""
    echo "  Deployment Order: VPC → EKS → NodeGroup → Addons"
    echo "  Destroy Order:    [Addons + NodeGroup] → EKS → VPC"
    echo "                    (Phase 1 runs in PARALLEL for speed)"
    echo ""

    for stack in "$VPC_STACK" "$EKS_STACK" "$NODEGROUP_STACK" "$ADDONS_STACK"; do
        if stack_exists "$stack"; then
            status=$(aws cloudformation describe-stacks --stack-name "$stack" --region "$AWS_REGION" \
                --query 'Stacks[0].StackStatus' --output text)
            case $status in
                *COMPLETE)
                    echo -e "  ${GREEN}✓${NC} $stack: $status"
                    ;;
                *IN_PROGRESS)
                    echo -e "  ${YELLOW}⟳${NC} $stack: $status"
                    ;;
                *FAILED|*ROLLBACK*)
                    echo -e "  ${RED}✗${NC} $stack: $status"
                    ;;
                *)
                    echo -e "  ${YELLOW}?${NC} $stack: $status"
                    ;;
            esac
        else
            echo -e "  ${YELLOW}○${NC} $stack: NOT DEPLOYED"
        fi
    done
    echo ""
}

validate_templates() {
    print_step "Validating CloudFormation Templates"

    for template in "01-vpc.yaml" "02-eks-cluster.yaml" "03-nodegroup.yaml" "04-addons.yaml"; do
        echo "  Validating $template..."
        aws cloudformation validate-template \
            --template-body "file://${SCRIPT_DIR}/${template}" \
            --region "$AWS_REGION" > /dev/null
        echo -e "    ${GREEN}✓${NC} Valid"
    done

    print_success "All templates are valid!"
}

run_Devtron() {
    print_step "Running Devtron Pre-requisite Setup"

    OUTPUT_FILE="${SCRIPT_DIR}/Devtron-pre-requsit.txt"

    echo "  Downloading and running Devtron setup script..."
    echo "  Output will be saved to: $OUTPUT_FILE"
    echo ""

    # Run the command and capture output
    {
        echo "=========================================="
        echo "Devtron Pre-requisite Output"
        echo "Date: $(date)"
        echo "Cluster: $CLUSTER_NAME"
        echo "=========================================="
        echo ""

        curl -f -O https://raw.githubusercontent.com/devtron-labs/utilities/main/kubeconfig-exporter/kubernetes_export_sa.sh && \
        chmod +x kubernetes_export_sa.sh && \
        ./kubernetes_export_sa.sh cd-user devtroncd

    } > "$OUTPUT_FILE" 2>&1

    if [ $? -eq 0 ]; then
        print_success "Devtron pre-requisite completed!"
        echo ""
        echo "  Output saved to: $OUTPUT_FILE"
        echo ""
        echo "  Contents:"
        echo "  ----------------------------------------"
        cat "$OUTPUT_FILE"
        echo "  ----------------------------------------"
    else
        print_error "Devtron pre-requisite failed!"
        echo "  Check $OUTPUT_FILE for details"
    fi

    # Cleanup downloaded script
    rm -f kubernetes_export_sa.sh 2>/dev/null
}

# Verify AWS credentials
print_step "Verifying AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials not configured"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "  Account: $ACCOUNT_ID"

# Parse commands
COMMAND=${1:-help}
TARGET=${2:-all}

case $COMMAND in
    deploy)
        case $TARGET in
            vpc)
                deploy_vpc
                ;;
            eks)
                deploy_eks
                ;;
            nodegroup)
                deploy_nodegroup
                ;;
            addons)
                deploy_addons
                ;;
            all)
                # Interactive prompts for cluster name and region
                prompt_for_config

                START_TIME=$(date +%s)
                deploy_vpc
                deploy_eks
                deploy_nodegroup
                deploy_addons
                END_TIME=$(date +%s)
                DURATION=$((END_TIME - START_TIME))
                MINUTES=$((DURATION / 60))
                SECONDS=$((DURATION % 60))
                echo ""
                echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
                echo -e "${GREEN}║              FULL DEPLOYMENT COMPLETE!                         ║${NC}"
                echo -e "${GREEN}║              Time: ${MINUTES}m ${SECONDS}s                                        ║${NC}"
                echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
                echo ""
                echo "Verify cluster:"
                echo "  kubectl get nodes"
                echo "  kubectl get pods -A"
                echo ""
                echo "To destroy:"
                echo "  $0 destroy all"
                ;;
            *)
                print_error "Unknown target: $TARGET"
                usage
                ;;
        esac
        ;;
    destroy)
        case $TARGET in
            vpc)
                destroy_vpc
                ;;
            eks)
                destroy_eks
                ;;
            nodegroup)
                destroy_nodegroup
                ;;
            addons)
                destroy_addons
                ;;
            all)
                # Interactive prompts for cluster name and region
                prompt_for_destroy_config

                START_TIME=$(date +%s)
                echo ""
                print_step "FAST PARALLEL DESTROY MODE"
                echo ""
                echo "  Phase 1: Delete Addons + NodeGroup in PARALLEL"
                echo "  Phase 2: Delete EKS Cluster"
                echo "  Phase 3: Delete VPC"
                echo ""

                # Phase 1: Delete Addons and NodeGroup in PARALLEL (they don't depend on each other)
                print_step "Phase 1/3: Deleting Addons + NodeGroup in parallel..."
                ADDONS_STARTED=false
                NODEGROUP_STARTED=false

                if start_delete_stack "$ADDONS_STACK"; then
                    ADDONS_STARTED=true
                fi
                if start_delete_stack "$NODEGROUP_STACK"; then
                    NODEGROUP_STARTED=true
                fi

                # Wait for both to complete in parallel
                if [ "$ADDONS_STARTED" = true ] || [ "$NODEGROUP_STARTED" = true ]; then
                    wait_for_stacks_delete "$ADDONS_STACK" "$NODEGROUP_STACK"
                    print_success "Phase 1 complete: Addons + NodeGroup deleted!"
                else
                    echo "  No stacks to delete in Phase 1"
                fi

                # Phase 2: Delete EKS (depends on NodeGroup being gone)
                print_step "Phase 2/3: Deleting EKS Cluster..."
                if start_delete_stack "$EKS_STACK"; then
                    wait_for_stack "$EKS_STACK" "delete"
                    print_success "Phase 2 complete: EKS Cluster deleted!"
                else
                    echo "  EKS stack already deleted"
                fi

                # Phase 3: Delete VPC (depends on EKS being gone)
                print_step "Phase 3/3: Deleting VPC..."
                if start_delete_stack "$VPC_STACK"; then
                    wait_for_stack "$VPC_STACK" "delete"
                    print_success "Phase 3 complete: VPC deleted!"
                else
                    echo "  VPC stack already deleted"
                fi

                END_TIME=$(date +%s)
                DURATION=$((END_TIME - START_TIME))
                MINUTES=$((DURATION / 60))
                SECONDS=$((DURATION % 60))
                echo ""
                echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
                echo -e "${GREEN}║              ALL STACKS DESTROYED!                             ║${NC}"
                echo -e "${GREEN}║              Time: ${MINUTES}m ${SECONDS}s                                        ║${NC}"
                echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
                ;;
            *)
                print_error "Unknown target: $TARGET"
                usage
                ;;
        esac
        ;;
    status)
        show_status
        ;;
    validate)
        validate_templates
        ;;
    Devtron)
        run_Devtron
        ;;
    force-destroy)
        # Interactive prompts for cluster name and region
        prompt_for_destroy_config

        START_TIME=$(date +%s)
        echo ""
        print_step "FORCE DELETE MODE - Handling stuck stacks"
        echo ""
        echo "  This will force delete any stacks in DELETE_FAILED state"
        echo "  and delete remaining stacks in parallel where possible."
        echo ""

        # Phase 1: Force delete Addons and NodeGroup in parallel
        print_step "Phase 1/3: Force deleting Addons + NodeGroup..."
        force_delete_stack "$ADDONS_STACK" &
        PID1=$!
        force_delete_stack "$NODEGROUP_STACK" &
        PID2=$!
        wait $PID1 $PID2
        print_success "Phase 1 complete!"

        # Phase 2: Force delete EKS
        print_step "Phase 2/3: Force deleting EKS Cluster..."
        force_delete_stack "$EKS_STACK"
        print_success "Phase 2 complete!"

        # Phase 3: Force delete VPC
        print_step "Phase 3/3: Force deleting VPC..."
        force_delete_stack "$VPC_STACK"
        print_success "Phase 3 complete!"

        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))
        MINUTES=$((DURATION / 60))
        SECONDS=$((DURATION % 60))
        echo ""
        echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║              FORCE DELETE COMPLETE!                            ║${NC}"
        echo -e "${GREEN}║              Time: ${MINUTES}m ${SECONDS}s                                        ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
        ;;
    *)
        usage
        ;;
esac
