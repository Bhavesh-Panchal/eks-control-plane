#!/bin/bash
#############################################
# CloudFormation Sequential Deployment Script
# 5-Stack EKS Deployment
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
NODE_ARCHITECTURE="${NODE_ARCHITECTURE:-arm64}"
INSTANCE_TYPE="${INSTANCE_TYPE:-c7g.2xlarge}"
NODE_MIN_SIZE="${NODE_MIN_SIZE:-2}"
NODE_MAX_SIZE="${NODE_MAX_SIZE:-4}"
NODE_DESIRED_CAPACITY="${NODE_DESIRED_CAPACITY:-2}"
NODE_DISK_SIZE="${NODE_DISK_SIZE:-80}"
NODEGROUP_AZ_MODE="${NODEGROUP_AZ_MODE:-multi}"
TARGET_AZ="${TARGET_AZ:-us-east-1a}"
API_IP_RESTRICTION_ENABLED="${API_IP_RESTRICTION_ENABLED:-false}"
API_ALLOWED_CIDRS="${API_ALLOWED_CIDRS:-0.0.0.0/0}"
VPC_CIDR="${VPC_CIDR:-10.11.0.0/16}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTERACTIVE_MODE=false

# Check if env vars were explicitly set (for non-interactive mode)
ENV_CLUSTER_SET=false
ENV_REGION_SET=false
ENV_ARCH_SET=false
if [ -n "${CLUSTER_NAME+x}" ] && [ "$CLUSTER_NAME" != "my-eks-cluster" ]; then
    ENV_CLUSTER_SET=true
fi
if [ -n "${AWS_REGION+x}" ] && [ "$AWS_REGION" != "us-east-1" ]; then
    ENV_REGION_SET=true
fi
if [ -n "${NODE_ARCHITECTURE+x}" ] && [ "$NODE_ARCHITECTURE" != "arm64" ]; then
    ENV_ARCH_SET=true
fi

# Function to prompt for cluster name and region
prompt_for_config() {
    # Skip interactive prompts if all env vars are set
    if [ "$ENV_CLUSTER_SET" = true ] && [ "$ENV_REGION_SET" = true ]; then
        echo ""
        print_step "Using environment variables (non-interactive mode)"
        echo "  Cluster Name:       $CLUSTER_NAME"
        echo "  AWS Region:         $AWS_REGION"
        echo "  VPC CIDR:           $VPC_CIDR"
        echo "  VPC AZs:           3 (EKS requirement)"
        echo "  NodeGroup AZ Mode:  $NODEGROUP_AZ_MODE"
        if [ "$NODEGROUP_AZ_MODE" = "single" ]; then
            echo "  Target AZ:          $TARGET_AZ"
        fi
        echo "  Architecture:       $NODE_ARCHITECTURE"
        echo "  Instance Type:      $INSTANCE_TYPE"
        echo "  Node Disk Size:     ${NODE_DISK_SIZE}GB"
        echo "  Node Min Size:      $NODE_MIN_SIZE"
        echo "  Node Max Size:      $NODE_MAX_SIZE"
        echo "  Node Desired:       $NODE_DESIRED_CAPACITY"
        if [ "$API_IP_RESTRICTION_ENABLED" = "true" ]; then
            echo "  API IP Restriction: Enabled"
            echo "  Allowed CIDRs:      $API_ALLOWED_CIDRS"
        else
            echo "  API IP Restriction: Disabled (0.0.0.0/0)"
        fi
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

    # Prompt for VPC CIDR
    echo -e "${GREEN}Configure VPC CIDR Block${NC}"
    echo ""
    echo "  CIDR block for the VPC (must not conflict with existing networks)"
    echo ""
    echo "  Common private CIDR ranges:"
    echo "    • 10.0.0.0/16      - 10.0.0.0 to 10.0.255.255 (65,534 IPs)"
    echo "    • 10.11.0.0/16     - 10.11.0.0 to 10.11.255.255 (65,534 IPs) - default"
    echo "    • 10.100.0.0/16    - 10.100.0.0 to 10.100.255.255 (65,534 IPs)"
    echo "    • 172.16.0.0/16    - 172.16.0.0 to 172.16.255.255 (65,534 IPs)"
    echo "    • 172.20.0.0/16    - 172.20.0.0 to 172.20.255.255 (65,534 IPs)"
    echo "    • 192.168.0.0/16   - 192.168.0.0 to 192.168.255.255 (65,534 IPs)"
    echo ""
    echo "  Note: Subnets will use /20 prefixes (4,094 IPs each)"
    echo "        The VPC CIDR will be split into 6 subnets (3 public, 3 private)"
    echo ""
    read -p "  VPC CIDR [${VPC_CIDR}]: " INPUT_VPC_CIDR
    if [ -n "$INPUT_VPC_CIDR" ]; then
        # Basic CIDR validation (format: x.x.x.x/y)
        if [[ "$INPUT_VPC_CIDR" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
            VPC_CIDR="$INPUT_VPC_CIDR"
        else
            print_warning "Invalid CIDR format. Using default: ${VPC_CIDR}"
        fi
    fi

    echo ""

    # Prompt for node architecture
    echo -e "${GREEN}Select Node Architecture${NC}"
    echo ""
    echo "    1) arm64   - Graviton (c7g, m7g, t4g) — better price-performance"
    echo "    2) x86_64  - Intel/AMD (t3, m5, c5, m6i, c6i) — broader compatibility"
    echo ""
    read -p "  Select architecture [1-2, or press Enter for ${NODE_ARCHITECTURE}]: " ARCH_CHOICE

    case $ARCH_CHOICE in
        1) NODE_ARCHITECTURE="arm64" ;;
        2) NODE_ARCHITECTURE="x86_64" ;;
        "") ;; # Keep default
        *)
            if [ "$ARCH_CHOICE" = "arm64" ] || [ "$ARCH_CHOICE" = "x86_64" ]; then
                NODE_ARCHITECTURE="$ARCH_CHOICE"
            else
                print_warning "Invalid choice. Using default: $NODE_ARCHITECTURE"
            fi
            ;;
    esac

    # Set default instance type based on architecture
    if [ "$NODE_ARCHITECTURE" = "arm64" ]; then
        DEFAULT_INSTANCE="c7g.2xlarge"
    else
        DEFAULT_INSTANCE="m5.xlarge"
    fi
    INSTANCE_TYPE="$DEFAULT_INSTANCE"

    echo ""
    echo -e "${GREEN}Select Instance Type${NC}"
    echo ""
    if [ "$NODE_ARCHITECTURE" = "arm64" ]; then
        echo "  Recommended ARM (Graviton) types:"
        echo "    • t4g.medium / t4g.large      (burstable, dev/test)"
        echo "    • c7g.large / c7g.xlarge       (compute-optimized)"
        echo "    • c7g.2xlarge                  (compute-optimized, default)"
        echo "    • m7g.large / m7g.xlarge       (general purpose)"
    else
        echo "  Recommended x86 (Intel/AMD) types:"
        echo "    • t3.medium / t3.large         (burstable, dev/test)"
        echo "    • m5.large / m5.xlarge         (general purpose, default)"
        echo "    • m6i.large / m6i.xlarge       (latest gen general purpose)"
        echo "    • c5.large / c5.xlarge         (compute-optimized)"
    fi
    echo ""
    read -p "  Instance Type [${DEFAULT_INSTANCE}]: " INPUT_INSTANCE
    if [ -n "$INPUT_INSTANCE" ]; then
        INSTANCE_TYPE="$INPUT_INSTANCE"
    fi

    echo ""
    echo -e "${GREEN}Configure Node Disk Size${NC}"
    echo ""
    echo "  Disk size for node root volume (in GB)"
    echo "  Recommended: 80GB for most workloads"
    echo "  Range: 20-200 GB"
    echo ""
    read -p "  Disk Size [${NODE_DISK_SIZE}]: " INPUT_DISK
    if [ -n "$INPUT_DISK" ]; then
        # Validate disk size range (20-200 as per CloudFormation template)
        if [[ "$INPUT_DISK" =~ ^[0-9]+$ ]] && [ "$INPUT_DISK" -ge 20 ] && [ "$INPUT_DISK" -le 200 ]; then
            NODE_DISK_SIZE="$INPUT_DISK"
        else
            print_warning "Disk size must be between 20-200 GB. Using default: ${NODE_DISK_SIZE}GB"
        fi
    fi

    echo ""
    echo -e "${GREEN}Configure Node Group Auto-Scaling${NC}"
    echo ""
    echo "  Min Size:    Minimum number of nodes (cost saving during low traffic)"
    echo "  Desired:     Initial number of nodes to launch"
    echo "  Max Size:    Maximum number of nodes (handle peak load)"
    echo ""
    read -p "  Min Size [${NODE_MIN_SIZE}]: " INPUT_MIN
    if [ -n "$INPUT_MIN" ]; then
        NODE_MIN_SIZE="$INPUT_MIN"
    fi
    read -p "  Desired Size [${NODE_DESIRED_CAPACITY}]: " INPUT_DESIRED
    if [ -n "$INPUT_DESIRED" ]; then
        NODE_DESIRED_CAPACITY="$INPUT_DESIRED"
    fi
    read -p "  Max Size [${NODE_MAX_SIZE}]: " INPUT_MAX
    if [ -n "$INPUT_MAX" ]; then
        NODE_MAX_SIZE="$INPUT_MAX"
    fi

    # Validate: min <= desired <= max
    if [ "$NODE_MIN_SIZE" -gt "$NODE_DESIRED_CAPACITY" ]; then
        print_warning "Min size cannot be greater than desired. Adjusting desired to min."
        NODE_DESIRED_CAPACITY="$NODE_MIN_SIZE"
    fi
    if [ "$NODE_DESIRED_CAPACITY" -gt "$NODE_MAX_SIZE" ]; then
        print_warning "Desired size cannot be greater than max. Adjusting max to desired."
        NODE_MAX_SIZE="$NODE_DESIRED_CAPACITY"
    fi

    echo ""
    echo -e "${GREEN}Configure Node Group AZ Distribution${NC}"
    echo ""
    echo "  Select how nodes should be distributed across Availability Zones:"
    echo "    • multi  - Nodes across all 3 AZs (high availability, recommended)"
    echo "    • single - Nodes in a single AZ (cost savings for dev/test)"
    echo ""
    read -p "  AZ Mode [multi/single, or press Enter for multi]: " INPUT_AZ_MODE
    if [ -n "$INPUT_AZ_MODE" ]; then
        if [ "$INPUT_AZ_MODE" = "single" ] || [ "$INPUT_AZ_MODE" = "multi" ]; then
            NODEGROUP_AZ_MODE="$INPUT_AZ_MODE"
        else
            print_warning "Invalid choice. Using default: multi"
            NODEGROUP_AZ_MODE="multi"
        fi
    fi

    # If single AZ mode, prompt for target AZ
    if [ "$NODEGROUP_AZ_MODE" = "single" ]; then
        echo ""
        echo "  Select the Availability Zone for single-AZ deployment:"
        echo ""
        echo "  Common AZs for ${AWS_REGION}:"
        case $AWS_REGION in
            us-east-1)
                echo "    1) us-east-1a"
                echo "    2) us-east-1b"
                echo "    3) us-east-1c"
                echo "    4) us-east-1d"
                echo "    5) us-east-1e"
                echo "    6) us-east-1f"
                ;;
            us-east-2)
                echo "    1) us-east-2a"
                echo "    2) us-east-2b"
                echo "    3) us-east-2c"
                ;;
            us-west-2)
                echo "    1) us-west-2a"
                echo "    2) us-west-2b"
                echo "    3) us-west-2c"
                echo "    4) us-west-2d"
                ;;
            ap-south-1)
                echo "    1) ap-south-1a"
                echo "    2) ap-south-1b"
                echo "    3) ap-south-1c"
                ;;
            eu-west-1)
                echo "    1) eu-west-1a"
                echo "    2) eu-west-1b"
                echo "    3) eu-west-1c"
                ;;
            ap-southeast-1)
                echo "    1) ap-southeast-1a"
                echo "    2) ap-southeast-1b"
                echo "    3) ap-southeast-1c"
                ;;
            *)
                echo "    Enter your region's AZ name (e.g., ${AWS_REGION}a)"
                ;;
        esac
        echo ""
        read -p "  Target AZ [${TARGET_AZ}]: " INPUT_TARGET_AZ
        if [ -n "$INPUT_TARGET_AZ" ]; then
            TARGET_AZ="$INPUT_TARGET_AZ"
        fi
    fi

    echo ""
    echo -e "${GREEN}Configure EKS API Server IP Restriction${NC}"
    echo ""
    echo "  Restrict public access to EKS API server to specific IP addresses."
    echo "  Recommended for production environments to enhance security."
    echo ""
    echo "  Options:"
    echo "    • false - Allow public access from any IP (0.0.0.0/0)"
    echo "    • true  - Restrict to specific IPs only"
    echo ""
    read -p "  Enable IP Restriction [false/true, or press Enter for false]: " INPUT_IP_RESTRICTION
    if [ -n "$INPUT_IP_RESTRICTION" ]; then
        if [ "$INPUT_IP_RESTRICTION" = "true" ] || [ "$INPUT_IP_RESTRICTION" = "true" ]; then
            API_IP_RESTRICTION_ENABLED=true
        else
            API_IP_RESTRICTION_ENABLED=false
        fi
    fi

    # If IP restriction is enabled, prompt for CIDR blocks
    if [ "$API_IP_RESTRICTION_ENABLED" = "true" ]; then
        echo ""
        echo "  Enter allowed CIDR blocks (comma-separated)"
        echo ""
        echo "  IMPORTANT: Only REAL public IP addresses are allowed!"
        echo "  AWS rejects private IPs (10.x, 172.16-31.x, 192.168.x) and documentation ranges."
        echo ""
        echo "  Examples:"
        echo "    • Single IP:       1.2.3.4/32"
        echo "    • Multiple IPs:    1.2.3.4/32,5.6.7.8/32"
        echo ""
        echo "  Your current public IP (for reference):"
        CURRENT_IP=$(curl -s https://checkip.amazonaws.com 2>/dev/null || echo "Unable to detect")
        echo "    $CURRENT_IP"
        echo ""
        read -p "  Allowed CIDRs: " INPUT_CIDRS
        if [ -n "$INPUT_CIDRS" ]; then
            API_ALLOWED_CIDRS="$INPUT_CIDRS"
        fi
    fi

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Configuration Summary:${NC}"
    echo -e "    Cluster Name:       ${YELLOW}${CLUSTER_NAME}${NC}"
    echo -e "    AWS Region:         ${YELLOW}${AWS_REGION}${NC}"
    echo -e "    VPC CIDR:           ${YELLOW}${VPC_CIDR}${NC}"
    echo -e "    VPC AZs:           ${YELLOW}3${NC} (EKS requirement)"
    echo -e "    NodeGroup AZ Mode:  ${YELLOW}${NODEGROUP_AZ_MODE}${NC}"
    if [ "$NODEGROUP_AZ_MODE" = "single" ]; then
        echo -e "    Target AZ:          ${YELLOW}${TARGET_AZ}${NC}"
    fi
    echo -e "    Architecture:       ${YELLOW}${NODE_ARCHITECTURE}${NC}"
    echo -e "    Instance Type:      ${YELLOW}${INSTANCE_TYPE}${NC}"
    echo -e "    Node Disk Size:     ${YELLOW}${NODE_DISK_SIZE}GB${NC}"
    echo -e "    Node Group:         Min=${YELLOW}${NODE_MIN_SIZE}${NC}, Desired=${YELLOW}${NODE_DESIRED_CAPACITY}${NC}, Max=${YELLOW}${NODE_MAX_SIZE}${NC}"
    if [ "$API_IP_RESTRICTION_ENABLED" = "true" ]; then
        echo -e "    API IP Restriction: ${YELLOW}Enabled${NC}"
        echo -e "    Allowed CIDRs:      ${YELLOW}${API_ALLOWED_CIDRS}${NC}"
    else
        echo -e "    API IP Restriction: ${YELLOW}Disabled${NC} (0.0.0.0/0)"
    fi
    echo ""
    echo -e "  Resources to be created:"
    echo -e "    • VPC:        ${CLUSTER_NAME}-vpc (3 AZs)"
    echo -e "    • EKS:        ${CLUSTER_NAME}-eks"
    echo -e "    • NodeGroup:  ${CLUSTER_NAME}-nodegroup (${NODEGROUP_AZ_MODE}-AZ)"
    echo -e "    • Addons:     ${CLUSTER_NAME}-addons"
    echo -e "    • LB Ctrl:    ${CLUSTER_NAME}-lb-controller"
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
    LB_CONTROLLER_STACK="${CLUSTER_NAME}-lb-controller"
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
        echo -e "    • ${LB_CONTROLLER_STACK}"
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
    echo -e "      • ${LB_CONTROLLER_STACK}"
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
LB_CONTROLLER_STACK="${CLUSTER_NAME}-lb-controller"

echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║       AWS EKS CloudFormation 5-Stack Deployment                ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  Stack 1: VPC (subnets, NAT, routes, EFS)                      ║"
echo "║  Stack 2: EKS Cluster + Non-Node Addons                        ║"
echo "║  Stack 3: Node Group                                           ║"
echo "║  Stack 4: Node-Dependent Addons + EFS StorageClass             ║"
echo "║  Stack 5: AWS Load Balancer Controller + Helm Install          ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  AUTO-INSTALL: Helm charts, K8s StorageClass                   ║"
echo "║  FAST DESTROY: Stacks 3+4+5 deleted in PARALLEL                ║"
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
    echo "  vpc               Stack 1: VPC, subnets, NAT Gateway, route tables, EFS"
    echo "  eks               Stack 2: EKS Cluster + vpc-cni, kube-proxy, pod-identity"
    echo "  nodegroup         Stack 3: Managed Node Group"
    echo "  addons            Stack 4: coredns, metrics-server, ebs-csi, efs-csi + StorageClass"
    echo "  lb-controller     Stack 5: AWS Load Balancer Controller IAM + Helm install"
    echo "  all               All stacks in sequence"
    echo ""
    echo "Examples:"
    echo "  $0 deploy vpc        # Deploy VPC only"
    echo "  $0 deploy eks        # Deploy EKS cluster + non-node addons"
    echo "  $0 deploy nodegroup  # Deploy node group"
    echo "  $0 deploy addons     # Deploy node-dependent addons + EFS StorageClass"
    echo "  \$0 deploy lb-controller  # Deploy LB Controller IAM + install via Helm"
    echo "  \$0 deploy all        # Deploy all 5 stacks sequentially + auto-install"
    echo ""
    echo "  \$0 destroy lb-controller  # Destroy Load Balancer Controller only"
    echo "  \$0 destroy addons    # Destroy addons only"
    echo "  \$0 destroy nodegroup # Destroy node group only"
    echo "  \$0 destroy eks       # Destroy EKS cluster only"
    echo "  \$0 destroy vpc       # Destroy VPC only"
    echo "  \$0 destroy all       # FAST: Parallel destroy (LB+Addons+NodeGroup together)"
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
    echo "  # VPC CIDR (for clients with existing CIDR conflicts)"
    echo "  VPC_CIDR=10.100.0.0/16 $0 deploy all"
    echo ""
    echo "  NODE_DISK_SIZE=100 NODE_MIN_SIZE=1 NODE_MAX_SIZE=5 NODE_DESIRED_CAPACITY=2 $0 deploy all"
    echo ""
    echo "  # NodeGroup AZ Configuration"
    echo "  NODEGROUP_AZ_MODE=single TARGET_AZ=us-west-2a $0 deploy all"
    echo ""
    echo "  # API Server IP Restriction (use REAL public IPs only)"
    echo "  API_IP_RESTRICTION_ENABLED=true API_ALLOWED_CIDRS='1.2.3.4/32,5.6.7.8/32' $0 deploy all"
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

    echo "  Creating VPC with 3 Availability Zones (EKS requirement)"
    echo "    VPC CIDR: $VPC_CIDR"

    if stack_exists "$VPC_STACK"; then
        print_warning "Stack $VPC_STACK already exists. Updating..."
        aws cloudformation update-stack \
            --stack-name "$VPC_STACK" \
            --template-body "file://${SCRIPT_DIR}/01-vpc.yaml" \
            --parameters \
                ParameterKey=ClusterName,ParameterValue="$CLUSTER_NAME" \
                ParameterKey=VpcCidr,ParameterValue="$VPC_CIDR" \
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
                ParameterKey=VpcCidr,ParameterValue="$VPC_CIDR" \
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

    # Show IP restriction status
    if [ "$API_IP_RESTRICTION_ENABLED" = "true" ]; then
        echo "  API Server IP Restriction: ${YELLOW}Enabled${NC}"
        echo "  Allowed CIDRs: ${API_ALLOWED_CIDRS}"
    else
        echo "  API Server IP Restriction: ${YELLOW}Disabled${NC} (allowing 0.0.0.0/0)"
    fi
    echo ""

    # Build parameters JSON (more reliable for complex values)
    PARAMS=$(cat <<EOF
[
    {"ParameterKey": "ClusterName", "ParameterValue": "${CLUSTER_NAME}"},
    {"ParameterKey": "EnableApiServerIpRestriction", "ParameterValue": "${API_IP_RESTRICTION_ENABLED}"},
    {"ParameterKey": "ApiServerPublicAccessCidrs", "ParameterValue": "${API_ALLOWED_CIDRS}"}
]
EOF
)

    if stack_exists "$EKS_STACK"; then
        print_warning "Stack $EKS_STACK already exists. Updating..."
        aws cloudformation update-stack \
            --stack-name "$EKS_STACK" \
            --template-body "file://${SCRIPT_DIR}/02-eks-cluster.yaml" \
            --parameters "$PARAMS" \
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
            --parameters "$PARAMS" \
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
                ParameterKey=Architecture,ParameterValue="$NODE_ARCHITECTURE" \
                ParameterKey=InstanceType,ParameterValue="$INSTANCE_TYPE" \
                ParameterKey=DiskSize,ParameterValue="$NODE_DISK_SIZE" \
                ParameterKey=MinSize,ParameterValue="$NODE_MIN_SIZE" \
                ParameterKey=MaxSize,ParameterValue="$NODE_MAX_SIZE" \
                ParameterKey=DesiredCapacity,ParameterValue="$NODE_DESIRED_CAPACITY" \
                ParameterKey=NodeGroupAZMode,ParameterValue="$NODEGROUP_AZ_MODE" \
                ParameterKey=TargetAZ,ParameterValue="$TARGET_AZ" \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$AWS_REGION" 2>/dev/null || {
                echo "  No updates needed or update in progress"
                return 0
            }
        wait_for_stack "$NODEGROUP_STACK" "update"
    else
        echo "  Creating Managed Node Group..."
        echo "    Architecture:     $NODE_ARCHITECTURE"
        echo "    Instance Type:    $INSTANCE_TYPE"
        echo "    Disk Size:        ${NODE_DISK_SIZE}GB"
        echo "    Scaling:          Min=$NODE_MIN_SIZE, Desired=$NODE_DESIRED_CAPACITY, Max=$NODE_MAX_SIZE"
        echo "    AZ Mode:          $NODEGROUP_AZ_MODE"
        if [ "$NODEGROUP_AZ_MODE" = "single" ]; then
            echo "    Target AZ:        $TARGET_AZ"
        fi
        echo "  This will take approximately 5-10 minutes..."

        aws cloudformation create-stack \
            --stack-name "$NODEGROUP_STACK" \
            --template-body "file://${SCRIPT_DIR}/03-nodegroup.yaml" \
            --parameters \
                ParameterKey=ClusterName,ParameterValue="$CLUSTER_NAME" \
                ParameterKey=Architecture,ParameterValue="$NODE_ARCHITECTURE" \
                ParameterKey=InstanceType,ParameterValue="$INSTANCE_TYPE" \
                ParameterKey=DiskSize,ParameterValue="$NODE_DISK_SIZE" \
                ParameterKey=MinSize,ParameterValue="$NODE_MIN_SIZE" \
                ParameterKey=MaxSize,ParameterValue="$NODE_MAX_SIZE" \
                ParameterKey=DesiredCapacity,ParameterValue="$NODE_DESIRED_CAPACITY" \
                ParameterKey=NodeGroupAZMode,ParameterValue="$NODEGROUP_AZ_MODE" \
                ParameterKey=TargetAZ,ParameterValue="$TARGET_AZ" \
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

    # Create EFS StorageClass (EFS CSI driver is part of addons)
    echo ""
    create_efs_storage_class
}

install_lb_controller_helm() {
    print_step "Installing AWS Load Balancer Controller via Helm"

    # Check if helm is installed
    if ! command -v helm &> /dev/null; then
        print_error "helm is not installed. Please install helm first."
        echo "  See: https://helm.sh/docs/intro/install/"
        return 1
    fi

    # Add EKS Helm repo
    echo "  Adding EKS Helm repository..."
    helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
    helm repo update > /dev/null

    # Get required values from CloudFormation outputs
    local vpc_id=$(aws cloudformation describe-stacks --stack-name "$VPC_STACK" --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' --output text 2>/dev/null)

    local lb_role_arn=$(aws cloudformation describe-stacks --stack-name "$LB_CONTROLLER_STACK" --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerControllerRoleArn`].OutputValue' --output text 2>/dev/null)

    if [ -z "$vpc_id" ] || [ -z "$lb_role_arn" ]; then
        print_error "Failed to get required values from CloudFormation outputs"
        return 1
    fi

    # Check if already installed
    if helm get notes aws-load-balancer-controller -n kube-system &> /dev/null; then
        echo "  AWS Load Balancer Controller already installed. Upgrading..."
        helm upgrade aws-load-balancer-controller eks/aws-load-balancer-controller \
            -n kube-system \
            --set clusterName="$CLUSTER_NAME" \
            --set serviceAccount.create=true \
            --set serviceAccount.name=aws-load-balancer-controller \
            --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$lb_role_arn" \
            --set region="$AWS_REGION" \
            --set vpcId="$vpc_id"
    else
        echo "  Installing AWS Load Balancer Controller..."
        helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
            -n kube-system \
            --set clusterName="$CLUSTER_NAME" \
            --set serviceAccount.create=true \
            --set serviceAccount.name=aws-load-balancer-controller \
            --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$lb_role_arn" \
            --set region="$AWS_REGION" \
            --set vpcId="$vpc_id"
    fi

    print_success "AWS Load Balancer Controller installed via Helm!"

    # Verify deployment
    echo ""
    echo "  Verifying deployment..."
    kubectl get deployment -n kube-system aws-load-balancer-controller
}

create_efs_storage_class() {
    print_step "Creating EFS Storage Class"

    # Get EFS ID from VPC stack outputs
    local efs_id=$(aws cloudformation describe-stacks --stack-name "$VPC_STACK" --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`EfsFileSystemId`].OutputValue' --output text 2>/dev/null)

    if [ -z "$efs_id" ]; then
        print_error "Failed to get EFS ID from CloudFormation outputs"
        return 1
    fi

    echo "  EFS File System ID: $efs_id"

    # Create StorageClass manifest
    local sc_manifest="${SCRIPT_DIR}/tmp/efs-storage-class.yaml"
    mkdir -p "${SCRIPT_DIR}/tmp"

    cat > "$sc_manifest" << EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: ${efs_id}
  directoryPerms: "700"
reclaimPolicy: Retain
volumeBindingMode: Immediate
EOF

    # Apply the StorageClass
    if kubectl apply -f "$sc_manifest"; then
        print_success "EFS StorageClass created successfully!"
        echo ""
        echo "  StorageClass details:"
        kubectl get storageclass efs-sc
    else
        print_error "Failed to create EFS StorageClass"
        return 1
    fi
}

deploy_lb_controller() {
    print_step "Stack 5/5: Deploying AWS Load Balancer Controller: $LB_CONTROLLER_STACK"

    # Verify EKS stack exists (cluster must be ready)
    if ! stack_exists "$EKS_STACK"; then
        print_error "EKS stack ($EKS_STACK) must be deployed first!"
        echo "  Run: $0 deploy eks"
        exit 1
    fi

    if stack_exists "$LB_CONTROLLER_STACK"; then
        print_warning "Stack $LB_CONTROLLER_STACK already exists. Updating..."
        aws cloudformation update-stack \
            --stack-name "$LB_CONTROLLER_STACK" \
            --template-body "file://${SCRIPT_DIR}/05-load-balancer-controller.yaml" \
            --parameters \
                ParameterKey=ClusterName,ParameterValue="$CLUSTER_NAME" \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$AWS_REGION" 2>/dev/null || {
                echo "  No updates needed or update in progress"
        }
        wait_for_stack "$LB_CONTROLLER_STACK" "update"
    else
        echo "  Creating AWS Load Balancer Controller IAM resources..."
        echo "    - IAM Policy for Load Balancer Controller"
        echo "    - IAM Role with IRSA for service account"
        echo ""

        aws cloudformation create-stack \
            --stack-name "$LB_CONTROLLER_STACK" \
            --template-body "file://${SCRIPT_DIR}/05-load-balancer-controller.yaml" \
            --parameters \
                ParameterKey=ClusterName,ParameterValue="$CLUSTER_NAME" \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$AWS_REGION"

        wait_for_stack "$LB_CONTROLLER_STACK" "create"
    fi

    print_success "AWS Load Balancer Controller IAM setup completed!"

    # Auto-install via Helm
    echo ""
    install_lb_controller_helm
}

# Function to uninstall Helm charts with user confirmation
uninstall_helm_charts() {
    # Check if helm is installed
    if ! command -v helm &> /dev/null; then
        echo "  Helm not found. Skipping Helm chart cleanup."
        return 0
    fi

    # Get list of installed Helm releases
    local helm_list=$(helm list -A --output json 2>/dev/null)

    if [ -z "$helm_list" ]; then
        echo "  No Helm releases found. Skipping..."
        return 0
    fi

    # Count releases
    local release_count=$(echo "$helm_list" | jq '. | length' 2>/dev/null || echo "0")

    if [ "$release_count" = "0" ]; then
        echo "  No Helm releases found. Skipping..."
        return 0
    fi

    echo ""
    print_step "Found ${release_count} Helm Release(s)"

    # Display all Helm releases
    echo ""
    echo -e "${CYAN}  Installed Helm Releases:${NC}"
    echo "  ┌─────────────────────────────────────────────────────────────────┐"
    echo "  │ NAME                       NAMESPACE       REVISION  UPDATED     │"
    echo "  ├─────────────────────────────────────────────────────────────────┤"

    echo "$helm_list" | jq -r '.[] | "  │ \(.name[:25])[:25]   \(.namespace[:14])[:14]   \(.revision | tostring[:9])[:9]   \(.updated | split(" ")[0][:10])     │"' 2>/dev/null || \
        helm list -A 2>/dev/null | tail -n +2 | while read line; do
            echo "  │ $line                                               │"
        done
    echo "  └─────────────────────────────────────────────────────────────────┘"
    echo ""

    # Ask user for confirmation
    echo -e "${YELLOW}WARNING: This will uninstall Helm releases from the cluster.${NC}"
    echo ""
    echo "  Options:"
    echo "    • all     - Uninstall ALL Helm releases"
    echo "    • deploy  - Uninstall only releases created by deploy.sh (aws-load-balancer-controller)"
    echo "    • skip    - Skip Helm cleanup (manual cleanup required)"
    echo ""
    read -p "  Uninstall Helm releases? [all/deploy/skip] [skip]: " HELM_CHOICE

    case "$HELM_CHOICE" in
        all|All|ALL)
            echo ""
            print_step "Uninstalling ALL Helm releases..."

            # Uninstall all releases
            echo "$helm_list" | jq -r '.[] | "\(.name);\(.namespace)"' 2>/dev/null | while IFS=';' read -r name namespace; do
                if [ -n "$name" ] && [ -n "$namespace" ]; then
                    echo "  Uninstalling $name from $namespace..."
                    helm uninstall "$name" -n "$namespace" 2>/dev/null || true
                fi
            done

            print_success "All Helm releases uninstalled!"
            ;;

        deploy|Deploy|DEPLOY)
            echo ""
            print_step "Uninstalling deploy.sh managed Helm releases..."

            # Only uninstall aws-load-balancer-controller
            if helm list -n kube-system | grep -q "aws-load-balancer-controller"; then
                echo "  Uninstalling aws-load-balancer-controller from kube-system..."
                helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true
                print_success "deploy.sh Helm releases uninstalled!"
            else
                echo "  No deploy.sh managed Helm releases found."
            fi
            ;;

        skip|Skip|SKIP|"")
            echo ""
            print_warning "Skipping Helm cleanup. You may need to manually uninstall releases."
            echo "  To list releases: helm list -A"
            echo "  To uninstall: helm uninstall <release-name> -n <namespace>"
            ;;

        *)
            echo ""
            print_warning "Invalid choice. Skipping Helm cleanup."
            ;;
    esac

    echo ""
}

# Function to cleanup EBS volumes created by Kubernetes
cleanup_ebs_volumes() {
    print_step "Cleaning up EBS Volumes"

    # Find volumes tagged with the cluster name
    local volumes=$(aws ec2 describe-volumes \
        --region "$AWS_REGION" \
        --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" \
                  "Name=status,Values=available" \
        --query "Volumes[*].[VolumeId,Size,Tags[?Key==`kubernetes.io-created-for-pvc-name`].Value|[0]]" \
        --output text 2>/dev/null)

    if [ -z "$volumes" ]; then
        echo "  No EBS volumes found for cluster: $CLUSTER_NAME"
        return 0
    fi

    # Count volumes
    local volume_count=$(echo "$volumes" | wc -l)
    echo ""
    echo -e "${CYAN}  Found ${volume_count} unattached EBS volume(s):${NC}"
    echo "  ┌─────────────────────────────────────────────────────────────────┐"
    echo "  │ VOLUME ID           SIZE (GB)   PVC NAME                         │"
    echo "  ├─────────────────────────────────────────────────────────────────┤"

    echo "$volumes" | while read -r vol_id size pvc_name; do
        if [ -n "$vol_id" ]; then
            pvc_display="${pvc_name:-N/A}"
            printf "  │ %-19s %-11s %-32s │\n" "$vol_id" "${size}GB" "$pvc_display"
        fi
    done
    echo "  └─────────────────────────────────────────────────────────────────┘"
    echo ""

    # Ask for confirmation
    echo -e "${YELLOW}These volumes will be permanently deleted!${NC}"
    echo "  • Volumes are unattached (status=available)"
    echo "  • Tagged with: kubernetes.io/cluster/${CLUSTER_NAME}=owned"
    echo ""
    read -p "  Delete these volumes? [yes/no] [no]: " DELETE_VOLUMES

    case "$DELETE_VOLUMES" in
        yes|Yes|YES)
            echo ""
            print_step "Deleting EBS volumes..."

            local deleted_count=0
            local failed_count=0

            echo "$volumes" | while read -r vol_id size pvc_name; do
                if [ -n "$vol_id" ]; then
                    if aws ec2 delete-volume --volume-id "$vol_id" --region "$AWS_REGION" 2>/dev/null; then
                        echo "  ${GREEN}✓${NC} Deleted: $vol_id (${size}GB) - ${pvc_name:-N/A}"
                        ((deleted_count++))
                    else
                        echo "  ${RED}✗${NC} Failed: $vol_id"
                        ((failed_count++))
                    fi
                fi
            done

            echo ""
            print_success "EBS volume cleanup completed!"
            ;;

        *)
            echo ""
            print_warning "Skipping EBS volume cleanup."
            echo "  To list manually:"
            echo "    aws ec2 describe-volumes --region $AWS_REGION \\"
            echo "      --filters Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned"
            echo ""
            ;;
    esac

    echo ""
}

destroy_lb_controller() {
    print_step "Destroying AWS Load Balancer Controller Stack: $LB_CONTROLLER_STACK"

    # Uninstall only the LB Controller Helm chart (managed by deploy.sh)
    if command -v helm &> /dev/null; then
        if helm get notes aws-load-balancer-controller -n kube-system &> /dev/null; then
            echo "  Uninstalling AWS Load Balancer Controller Helm chart..."
            helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true
        fi
    fi

    if ! stack_exists "$LB_CONTROLLER_STACK"; then
        print_warning "Stack $LB_CONTROLLER_STACK does not exist. Skipping..."
        return 0
    fi

    aws cloudformation delete-stack --stack-name "$LB_CONTROLLER_STACK" --region "$AWS_REGION"
    wait_for_stack "$LB_CONTROLLER_STACK" "delete"

    print_success "AWS Load Balancer Controller Stack destroyed successfully!"
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
    echo "  Deployment Order: VPC → EKS → NodeGroup → Addons → LB Controller"
    echo "  Destroy Order:    [LB Controller + Addons + NodeGroup] → EKS → VPC"
    echo "                    (Phase 1 runs in PARALLEL for speed)"
    echo ""

    for stack in "$VPC_STACK" "$EKS_STACK" "$NODEGROUP_STACK" "$ADDONS_STACK" "$LB_CONTROLLER_STACK"; do
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

    for template in "01-vpc.yaml" "02-eks-cluster.yaml" "03-nodegroup.yaml" "04-addons.yaml" "05-load-balancer-controller.yaml"; do
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
            lb-controller)
                deploy_lb_controller
                ;;
            all)
                # Interactive prompts for cluster name and region
                prompt_for_config

                START_TIME=$(date +%s)
                deploy_vpc
                deploy_eks
                deploy_nodegroup
                deploy_addons
                deploy_lb_controller
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
            lb-controller)
                destroy_lb_controller
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
                echo "  Phase 0: Helm Chart Cleanup"
                echo "  Phase 1: Delete LB Controller + Addons + NodeGroup in PARALLEL"
                echo "  Phase 2: Delete EKS Cluster"
                echo "  Phase 3: Delete VPC"
                echo "  Phase 4: Cleanup EBS Volumes"
                echo ""

                # Phase 0: Uninstall Helm charts
                uninstall_helm_charts

                # Phase 1: Delete LB Controller, Addons and NodeGroup in PARALLEL (they don't depend on each other)
                print_step "Phase 1/4: Deleting LB Controller + Addons + NodeGroup in parallel..."
                LB_CONTROLLER_STARTED=false
                ADDONS_STARTED=false
                NODEGROUP_STARTED=false

                if start_delete_stack "$LB_CONTROLLER_STACK"; then
                    LB_CONTROLLER_STARTED=true
                fi
                if start_delete_stack "$ADDONS_STACK"; then
                    ADDONS_STARTED=true
                fi
                if start_delete_stack "$NODEGROUP_STACK"; then
                    NODEGROUP_STARTED=true
                fi

                # Wait for all three to complete in parallel
                if [ "$LB_CONTROLLER_STARTED" = true ] || [ "$ADDONS_STARTED" = true ] || [ "$NODEGROUP_STARTED" = true ]; then
                    wait_for_stacks_delete "$LB_CONTROLLER_STACK" "$ADDONS_STACK" "$NODEGROUP_STACK"
                    print_success "Phase 1 complete: LB Controller + Addons + NodeGroup deleted!"
                else
                    echo "  No stacks to delete in Phase 1"
                fi

                # Phase 2: Delete EKS (depends on NodeGroup being gone)
                print_step "Phase 2/4: Deleting EKS Cluster..."
                if start_delete_stack "$EKS_STACK"; then
                    wait_for_stack "$EKS_STACK" "delete"
                    print_success "Phase 2 complete: EKS Cluster deleted!"
                else
                    echo "  EKS stack already deleted"
                fi

                # Phase 3: Delete VPC (depends on EKS being gone)
                print_step "Phase 3/4: Deleting VPC..."
                if start_delete_stack "$VPC_STACK"; then
                    wait_for_stack "$VPC_STACK" "delete"
                    print_success "Phase 3 complete: VPC deleted!"
                else
                    echo "  VPC stack already deleted"
                fi

                # Phase 4: Cleanup EBS volumes (only after all resources are deleted)
                cleanup_ebs_volumes

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

        # Phase 1: Force delete LB Controller, Addons and NodeGroup in parallel
        print_step "Phase 1/4: Force deleting LB Controller + Addons + NodeGroup..."
        force_delete_stack "$LB_CONTROLLER_STACK" &
        PID1=$!
        force_delete_stack "$ADDONS_STACK" &
        PID2=$!
        force_delete_stack "$NODEGROUP_STACK" &
        PID3=$!
        wait $PID1 $PID2 $PID3
        print_success "Phase 1 complete!"

        # Phase 2: Force delete EKS
        print_step "Phase 2/4: Force deleting EKS Cluster..."
        force_delete_stack "$EKS_STACK"
        print_success "Phase 2 complete!"

        # Phase 3: Force delete VPC
        print_step "Phase 3/4: Force deleting VPC..."
        force_delete_stack "$VPC_STACK"
        print_success "Phase 3 complete!"

        # Phase 4: Cleanup EBS volumes
        cleanup_ebs_volumes

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
