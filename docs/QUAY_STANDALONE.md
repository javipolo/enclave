# Red Hat Quay Standalone Installation

This document describes how to use the `quay-standalone.yaml` playbook to install and configure Red Hat Quay independently of the full enclave deployment process.

## Overview

The standalone Quay playbook (`playbooks/quay-standalone.yaml`) provides a focused installation and configuration of Red Hat Quay with the following features:

- **Operator Installation**: Installs the Quay operator from configured catalog sources
- **Storage Integration**: Automatically configures storage backends (LVMS/ODF) if present
- **User Management**: Creates initial admin user with configurable credentials
- **OAuth Configuration**: Sets up OAuth applications for API access
- **Disconnected Support**: Full support for air-gapped environments with image mirroring
- **Verification**: Built-in health checks and status verification

## Prerequisites

### Required
- OpenShift cluster deployed and accessible
- `oc` CLI tool configured with cluster admin access
- Working directory with enclave configuration files
- Required variables defined (see Configuration section)

### Recommended
- Storage backend (LVMS or ODF) pre-configured for persistent storage
- DNS resolution configured for Quay route
- Sufficient cluster resources (minimum 4 CPU cores, 8GB RAM for Quay components)

## Configuration

### Required Variables

The following variables must be defined either via `-e` flags or in your configuration files:

```yaml
# Working directory containing cluster config and binaries
workingDir: /home/cloud-user

# Cluster information
clusterName: my-cluster
baseDomain: example.com

# Quay admin credentials
quayUser: quayadmin
quayPassword: mySecurePassword123
```

### Optional Variables

```yaml
# Deployment mode (default: true)
disconnected: true

# Storage plugin (auto-detected if not specified)
storage_plugin: lvms  # or 'odf'

# OAuth application configuration (from defaults/quay_operator.yaml)
quayOAuthApp:
  enabled: true
  name: "default-application"
  organization: "default-org"
  redirect_uri: "http://localhost:8080/callback"
  scopes: "repo:read repo:write repo:admin repo:create user:read user:admin org:admin"

# Namespace configuration
quay_namespace: quay-enterprise
quay_operator_namespace: openshift-operators
```

## Usage

### Basic Installation (Disconnected Mode)

```bash
# Install Quay in disconnected mode with default configuration
ansible-playbook playbooks/quay-standalone.yaml -e workingDir=/home/cloud-user
```

### Connected Mode Installation

```bash
# Install Quay in connected mode (pulls images from upstream)
ansible-playbook playbooks/quay-standalone.yaml \
  -e workingDir=/home/cloud-user \
  -e disconnected=false
```

### Custom Configuration

```bash
# Install with custom credentials and configuration
ansible-playbook playbooks/quay-standalone.yaml \
  -e workingDir=/home/cloud-user \
  -e quayUser=admin \
  -e quayPassword=myPassword \
  -e storage_plugin=odf
```

### Tag-Based Execution

The playbook supports selective execution using tags:

```bash
# Install only the operator
ansible-playbook playbooks/quay-standalone.yaml -e workingDir=/home/cloud-user --tags quay-operator

# Configure only storage
ansible-playbook playbooks/quay-standalone.yaml -e workingDir=/home/cloud-user --tags quay-storage

# Run verification only
ansible-playbook playbooks/quay-standalone.yaml -e workingDir=/home/cloud-user --tags quay-verify

# Skip OAuth configuration
ansible-playbook playbooks/quay-standalone.yaml -e workingDir=/home/cloud-user --skip-tags quay-oauth
```

Available tags:
- `quay-operator`: Operator installation and readiness checks
- `quay-namespace`: Namespace creation
- `quay-storage`: Storage backend configuration
- `quay-registry`: QuayRegistry resource creation and configuration
- `quay-config`: Quay configuration secret management
- `quay-oauth`: OAuth application setup
- `quay-verify`: Health checks and verification

## Installation Process

The playbook executes the following phases:

### Phase 1: Operator Installation
1. Creates the `quay-enterprise` namespace
2. Installs the Quay operator via existing operator configuration tasks
3. Waits for the operator to reach `Succeeded` state

### Phase 2: Storage Backend Configuration
1. Auto-detects configured storage plugin (LVMS/ODF)
2. Runs storage-specific Quay preparation tasks
3. Ensures storage classes and resources are available

### Phase 3: Quay Registry Configuration
1. Creates initial Quay configuration secret
2. Deploys QuayRegistry custom resource
3. Waits for Quay components to become available
4. Creates initial admin user
5. Configures OAuth application (if enabled)
6. Updates cluster pull secret with Quay credentials

### Phase 4: Disconnected Setup (if enabled)
1. Configures container registries for mirroring
2. Runs `oc-mirror` to populate Quay with required images
3. Applies ImageDigestMirrorSet (IDMS) and ImageTagMirrorSet (ITMS)
4. Configures cluster trust for Quay CA certificate

### Phase 5: Verification and Reporting
1. Checks QuayRegistry status and conditions
2. Performs health check against Quay API
3. Displays installation summary with access information

## Post-Installation

### Accessing Quay

After successful installation, Quay will be available at:
```
https://registry-quay-quay-enterprise.apps.<clusterName>.<baseDomain>
```

Log in using the configured admin credentials:
- Username: `<quayUser>`
- Password: `<quayPassword>`

### Configuration Files Created

The playbook creates the following files in your working directory:

- `config/pull-secret.quay.json`: Pull secret with Quay registry credentials
- `logs/oc-mirror.progress.quay.<timestamp>.log`: Mirror operation logs (disconnected mode)

### Kubernetes Secrets Created

- `quay-initial-user-token` (namespace: quay-enterprise): Initial user access token
- `quay-oauth-credentials` (namespace: quay-enterprise): OAuth application credentials
- `pull-secret` (namespace: openshift-config): Updated cluster pull secret

## Troubleshooting

### Common Issues

**Operator Installation Fails**
```bash
# Check operator subscription status
oc get subscription quay-operator -n openshift-operators
oc describe subscription quay-operator -n openshift-operators

# Check install plan
oc get installplan -n openshift-operators
```

**QuayRegistry Not Available**
```bash
# Check QuayRegistry status
oc get quayregistry registry -n quay-enterprise -o yaml

# Check Quay operator logs
oc logs deployment/quay-operator -n openshift-operators
```

**Storage Issues**
```bash
# Verify storage classes
oc get storageclass

# Check PVC status
oc get pvc -n quay-enterprise
```

**Route/Certificate Issues**
```bash
# Check route status
oc get route -n quay-enterprise
oc describe route registry-quay -n quay-enterprise

# Test connectivity
curl -k https://registry-quay-quay-enterprise.apps.<cluster>.<domain>/health/instance
```

### Re-running Installation

To clean up and re-run installation:

```bash
# Delete QuayRegistry (preserves data if storage is persistent)
oc delete quayregistry registry -n quay-enterprise

# Delete namespace (removes all Quay resources)
oc delete namespace quay-enterprise

# Re-run playbook
ansible-playbook playbooks/quay-standalone.yaml -e workingDir=/home/cloud-user
```

### Logs and Diagnostics

View installation logs:
```bash
# Ansible execution logs
tail -f ~/.ansible/collections/ansible_collections/redhat/enclave/playbooks/quay-standalone.yaml.log

# Quay operator logs
oc logs -f deployment/quay-operator -n openshift-operators

# Mirror operation logs (disconnected mode)
tail -f <workingDir>/logs/oc-mirror.progress.quay.<timestamp>.log
```

## Integration with Full Enclave

The standalone Quay playbook uses the same tasks and configuration as the full enclave deployment (`playbooks/05-operators.yaml`). This ensures:

- **Consistency**: Same configuration and behavior across deployment methods
- **Compatibility**: Existing clusters can be upgraded using the full enclave playbook
- **Maintainability**: Single source of truth for Quay configuration

To integrate an existing Quay installation into the full enclave workflow:
1. Ensure your configuration files match the enclave defaults
2. Run the full enclave playbook with appropriate tags to skip Quay installation
3. The enclave will detect and use the existing Quay installation

## Related Documentation

- [QUAY_OAUTH_TOKEN_REGEN.md](./QUAY_OAUTH_TOKEN_REGEN.md): Regenerating OAuth tokens
- [LOCAL_TESTING.md](./LOCAL_TESTING.md): Local development and testing
- [CI_WORKFLOWS.md](./CI_WORKFLOWS.md): CI/CD integration examples