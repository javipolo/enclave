#!/bin/bash
#
# Quay Standalone Deployment Prerequisites Validator
#
# This script validates that all prerequisites are met before running
# the quay-standalone.yaml playbook.
#
# Usage:
#   ./scripts/validate-quay-prerequisites.sh [workingDir]
#
# Exit codes:
#   0 - All prerequisites met
#   1 - Missing prerequisites found
#   2 - Usage error

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default working directory
WORKING_DIR="${1:-$(pwd)}"

# Validation results
ERRORS=0
WARNINGS=0

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $*"
    ((WARNINGS++))
}

log_error() {
    echo -e "${RED}[✗]${NC} $*"
    ((ERRORS++))
}

check_command() {
    local cmd=$1
    local description=${2:-$cmd}

    if command -v "$cmd" >/dev/null 2>&1; then
        log_success "$description is available"
    else
        log_error "$description is not available in PATH"
    fi
}

check_file() {
    local file=$1
    local description=${2:-$file}

    if [[ -f "$file" ]]; then
        log_success "$description exists"
    else
        log_error "$description not found"
    fi
}

check_directory() {
    local dir=$1
    local description=${2:-$dir}

    if [[ -d "$dir" ]]; then
        log_success "$description exists"
    else
        log_error "$description not found"
    fi
}

check_oc_connectivity() {
    if oc whoami >/dev/null 2>&1; then
        local user=$(oc whoami)
        local server=$(oc whoami --show-server)
        log_success "Connected to OpenShift as '$user' ($server)"

        # Check cluster admin privileges
        if oc auth can-i '*' '*' --all-namespaces >/dev/null 2>&1; then
            log_success "Cluster admin privileges confirmed"
        else
            log_warning "Limited privileges detected. Some operations may fail."
        fi
    else
        log_error "Cannot connect to OpenShift cluster"
    fi
}

check_cluster_info() {
    if ! oc whoami >/dev/null 2>&1; then
        return 1
    fi

    local cluster_version
    cluster_version=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null)
    if [[ -n "$cluster_version" ]]; then
        log_success "OpenShift version: $cluster_version"
    else
        log_warning "Could not determine OpenShift version"
    fi

    # Check for storage classes
    local storage_classes
    storage_classes=$(oc get storageclass -o name | wc -l)
    if [[ "$storage_classes" -gt 0 ]]; then
        log_success "Storage classes available ($storage_classes found)"
        oc get storageclass -o custom-columns="NAME:.metadata.name,PROVISIONER:.provisioner,DEFAULT:.metadata.annotations.storageclass\.kubernetes\.io/is-default-class" --no-headers | while IFS= read -r line; do
            echo "    $line"
        done
    else
        log_warning "No storage classes found. Quay may need persistent storage."
    fi
}

check_required_variables() {
    local config_file="$WORKING_DIR/config/cluster.yaml"

    if [[ -f "$config_file" ]]; then
        log_success "Cluster configuration file found"

        # Check for required variables
        local required_vars=("clusterName" "baseDomain")
        for var in "${required_vars[@]}"; do
            if grep -q "^${var}:" "$config_file"; then
                local value=$(grep "^${var}:" "$config_file" | cut -d: -f2- | xargs)
                log_success "$var is configured: $value"
            else
                log_error "$var is not configured in $config_file"
            fi
        done
    else
        log_warning "Cluster configuration file not found at $config_file"
        log_info "You may need to specify cluster configuration via -e flags"
    fi

    # Check for Quay credentials
    local quay_config="$WORKING_DIR/config/quay.yaml"
    if [[ -f "$quay_config" ]]; then
        log_success "Quay configuration file found"
    else
        log_warning "Quay configuration file not found at $quay_config"
        log_info "You may need to specify quayUser and quayPassword via -e flags"
    fi
}

check_disk_space() {
    local available_space
    available_space=$(df "$WORKING_DIR" | awk 'NR==2 {print $4}')
    local available_gb=$((available_space / 1024 / 1024))

    if [[ "$available_gb" -gt 10 ]]; then
        log_success "Sufficient disk space available: ${available_gb}GB"
    elif [[ "$available_gb" -gt 5 ]]; then
        log_warning "Limited disk space available: ${available_gb}GB"
    else
        log_error "Insufficient disk space available: ${available_gb}GB (minimum 5GB recommended)"
    fi
}

check_network_connectivity() {
    if oc whoami >/dev/null 2>&1; then
        # Try to get cluster info as network test
        if oc get nodes >/dev/null 2>&1; then
            log_success "Network connectivity to cluster verified"
        else
            log_warning "Limited network connectivity to cluster"
        fi
    fi
}

print_summary() {
    echo ""
    echo "=========================================="
    echo "Quay Prerequisites Validation Summary"
    echo "=========================================="

    if [[ "$ERRORS" -eq 0 && "$WARNINGS" -eq 0 ]]; then
        log_success "All prerequisites met! Ready to deploy Quay."
        echo ""
        echo "To deploy Quay, run:"
        echo "  ansible-playbook playbooks/quay-standalone.yaml -e workingDir=$WORKING_DIR"
    elif [[ "$ERRORS" -eq 0 ]]; then
        log_warning "$WARNINGS warning(s) found. Deployment may proceed but review warnings."
        echo ""
        echo "To deploy Quay with warnings, run:"
        echo "  ansible-playbook playbooks/quay-standalone.yaml -e workingDir=$WORKING_DIR"
    else
        log_error "$ERRORS error(s) and $WARNINGS warning(s) found. Fix errors before deployment."
        echo ""
        echo "Please resolve the errors above before running the Quay deployment."
    fi

    echo ""
    echo "For more information, see: docs/QUAY_STANDALONE.md"
}

# Main validation
main() {
    echo "Validating Quay deployment prerequisites..."
    echo "Working directory: $WORKING_DIR"
    echo ""

    # Check working directory exists
    check_directory "$WORKING_DIR" "Working directory"

    # Check required commands
    log_info "Checking required commands..."
    check_command "ansible-playbook" "Ansible"
    check_command "oc" "OpenShift CLI"
    check_command "curl" "curl"
    check_command "jq" "jq (JSON processor)"

    echo ""

    # Check OpenShift connectivity
    log_info "Checking OpenShift connectivity..."
    check_oc_connectivity
    check_cluster_info

    echo ""

    # Check working directory structure
    log_info "Checking working directory structure..."
    check_directory "$WORKING_DIR/bin" "bin directory"
    check_directory "$WORKING_DIR/config" "config directory"
    check_file "$WORKING_DIR/bin/oc" "oc binary"

    echo ""

    # Check configuration
    log_info "Checking configuration..."
    check_required_variables

    echo ""

    # Check system resources
    log_info "Checking system resources..."
    check_disk_space
    check_network_connectivity

    echo ""

    # Check for existing Quay installation
    log_info "Checking for existing Quay installation..."
    if oc get namespace quay-enterprise >/dev/null 2>&1; then
        if oc get quayregistry registry -n quay-enterprise >/dev/null 2>&1; then
            log_warning "Existing QuayRegistry found in quay-enterprise namespace"
            log_info "The playbook will update the existing installation"
        else
            log_warning "quay-enterprise namespace exists but no QuayRegistry found"
        fi
    else
        log_success "No existing Quay installation found"
    fi

    print_summary
}

# Usage help
usage() {
    echo "Usage: $0 [workingDir]"
    echo ""
    echo "Validates prerequisites for Quay standalone deployment."
    echo ""
    echo "Arguments:"
    echo "  workingDir    Path to working directory (default: current directory)"
    echo ""
    echo "Examples:"
    echo "  $0                           # Use current directory"
    echo "  $0 /home/cloud-user         # Use specific working directory"
    exit 2
}

# Parse arguments
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
fi

# Validate working directory argument
if [[ $# -gt 1 ]]; then
    echo "Error: Too many arguments"
    usage
fi

if [[ -n "${1:-}" ]] && [[ ! -d "$1" ]]; then
    echo "Error: Working directory '$1' does not exist"
    exit 2
fi

# Run main validation
main

# Exit with appropriate code
if [[ "$ERRORS" -gt 0 ]]; then
    exit 1
else
    exit 0
fi