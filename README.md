# Tutor for K3s Kubernetes Management

This repository contains scripts to set up and run [Tutor](https://docs.tutor.overhang.io/) with a K3s Kubernetes cluster deployed using the [tfgrid-k3s](https://github.com/mik-tf/tfgrid-k3s) project in the same main directory.

## Project Tree

```
.
├── tfgrid-k3s
└── tutor-k3s
```

## Overview

Tutor is the official Docker-based Open edX distribution. This setup allows you to deploy Open edX on a K3s Kubernetes cluster running on ThreeFold Grid.

## Prerequisites

- A running K3s cluster deployed with the tfgrid-k3s project
- Python 3.6+ installed on your local machine
- kubectl installed on your local machine

## Setup

1. Make sure you have a running K3s cluster deployed with tfgrid-k3s
2. Run the setup script to configure the environment:

```bash
make setup
```

This will:
- Set up KUBECONFIG to point to your tfgrid-k3s cluster's k3s.yaml file
- Create a Python virtual environment
- Install tutor via pip

3. Prepare your Kubernetes cluster for Tutor:

```bash
make prepare
```

This will:
- Create the necessary 'openedx' namespace
- Install required Tutor plugins (mfe, indigo)
- Set up storage classes if needed
- Install an ingress controller if not present

## Usage

### Activating the Environment

After initial setup, you can activate the environment in future sessions.

For fish shell (recommended):

```fish
source activate.fish
```

For bash shell:

```bash
source activate.sh
```

This will:
- Set KUBECONFIG to point to the k3s.yaml in the tfgrid-k3s directory
- Activate the Python virtual environment with tutor installed

### Configuring Docker Registry Authentication

To avoid Docker Hub rate limits and authentication issues when pulling images, you should configure registry authentication before deploying Open edX. This is especially important for production environments.

The recommended approach is to use a Docker Hub access token instead of your password:

1. Create a Docker Hub access token at https://hub.docker.com/settings/security
   - Set the token description (e.g., "K3s OpenEdX Deployment")
   - Set access permissions to **Read-only** (minimum required)
     - For public repositories, you can use **Public repo read-only**
   - Set an appropriate expiration based on your security policies
2. Set the following environment variables (securely):

```bash
# For secure credential handling, use:
set +o history  # Disable command history
export DOCKER_USERNAME="your_dockerhub_username"
export DOCKER_TOKEN="your_dockerhub_token"
export DOCKER_EMAIL="your_email"
set -o history  # Re-enable command history
```

3. Run the registry authentication setup:

```bash
make registry-auth
```

This will create a Kubernetes secret with your Docker Hub credentials and configure all necessary service accounts to use it for pulling images.

> **Note**: The `make deploy` command automatically includes the registry authentication step, so you don't need to run it separately unless you want to update your credentials.

### Deploying Open edX

The deployment process has been automated with a comprehensive script. After activating the environment, simply run:

```bash
make deploy
```

This will:
1. Clean up any existing failed deployment
2. Create the openedx namespace if it doesn't exist
3. Install and enable required Tutor plugins (indigo, mfe)
4. Configure Tutor with proper hostnames (lms.local, studio.local)
5. Save the configuration
6. Deploy Open edX on Kubernetes
7. Wait for pods to be ready
8. Initialize Open edX
9. Provide access information

### Accessing Your Open edX Instance

After deployment, you'll need to set up local DNS or use port-forwarding to access your Open edX instance:

```bash
# Add to your /etc/hosts file
127.0.0.1 lms.local studio.local

# Port-forward the LMS service
kubectl port-forward -n openedx svc/lms 8000:8000

# In another terminal, port-forward the Studio service
kubectl port-forward -n openedx svc/cms 8001:8000
```

Then access:
- LMS (Learning Management System): http://lms.local:8000
- Studio (Content Management System): http://studio.local:8001

### Creating an Admin User

To create a superuser account for administrative access:

```bash
tutor k8s exec lms -- python manage.py lms createsuperuser
```

### Customizing Your Open edX Installation

You can customize your Open edX installation by editing the configuration:

```bash
# Edit configuration values
tutor config save --set PLATFORM_NAME="Your Platform Name"

# View current configuration
tutor config printvalue PLATFORM_NAME

# After making changes, redeploy
make deploy
```

Refer to the [official Tutor documentation](https://docs.tutor.overhang.io/) for more detailed instructions on using Tutor with Kubernetes.

## Troubleshooting

### Common Issues

#### ImagePullBackOff

If you see pods stuck in `ImagePullBackOff` status:

```
NAME                     READY   STATUS             RESTARTS   AGE
cms-8697d55fc8-wddfz     0/1     ImagePullBackOff   0          17m
```

This means Kubernetes is having trouble pulling the container images. Possible solutions:

1. **Configure Docker Registry Authentication**: The most reliable solution is to set up proper authentication:
   ```bash
   make registry-auth
   ```
   This creates the necessary Kubernetes secrets and configures service accounts to use them.

2. **Check Internet Connectivity**: Ensure your K3s nodes have internet access

3. **Docker Hub Rate Limits**: You might be hitting Docker Hub's rate limits. Solutions:
   - Use a Docker Hub account with higher rate limits
   - Use a private registry
   - Configure registry mirrors in your K3s setup

4. **File Descriptor Limits**: Open edX images contain thousands of files. If you see errors like `too many open files` in your pod status, your system's file descriptor limits are too low. Solutions:
   - The `prepare-k8s.sh` script now automatically checks and attempts to increase these limits
   - You can manually increase limits by adding to `/etc/security/limits.conf` or `/etc/security/limits.d/99-openedx-limits.conf`:
     ```
     * soft nofile 65535
     * hard nofile 65535
     root soft nofile 65535
     root hard nofile 65535
     ```
   - After changing limits, log out and back in, or restart your K3s service: `sudo systemctl restart k3s`

5. **Manual Image Pull**: Try manually pulling the image on your nodes
   ```bash
   # Find the image name
   kubectl describe pod -n openedx <pod-name> | grep Image:
   # Pull the image manually
   docker pull <image-name>
   ```

5. **Delete and Recreate**: Sometimes deleting the pod will trigger a successful retry
   ```bash
   kubectl delete pod -n openedx <pod-name>
   ```

#### CrashLoopBackOff

If pods are in `CrashLoopBackOff` status, check the logs:

```bash
kubectl logs -n openedx <pod-name>
```

For Caddy specifically, if you see `ambiguous site definition`, ensure your LMS_HOST and CMS_HOST are set to different values:

```bash
tutor config save --set LMS_HOST=lms.local
tutor config save --set CMS_HOST=studio.local
tutor k8s start
```

#### ContainerCreating or Pending

Pods stuck in these states might be waiting for:

1. **Resource constraints**: Check if your nodes have enough CPU/memory
2. **Volume issues**: Check if PersistentVolumeClaims are bound
3. **Dependent services**: Some pods depend on others (like MySQL) to be running first

Check events for more details:

```bash
kubectl get events -n openedx --sort-by=.metadata.creationTimestamp
```

### Resetting Your Deployment

If you need to start completely fresh (this will delete all data):

```bash
# Complete reset (interactive, will ask for confirmation)
make reset

# After reset, redeploy
make deploy
```

The reset process will:
1. Delete all resources in the openedx namespace (pods, services, deployments)
2. Delete all persistent volume claims (databases, uploaded files)
3. Delete all configmaps and secrets
4. Delete the namespace itself
5. Optionally reset Tutor configuration to defaults

This is useful when:
- You want to start from scratch with a clean installation
- You're experiencing persistent issues that can't be resolved otherwise
- You're testing the deployment process

### Additional Troubleshooting Steps

1. Verify your K3s cluster is running properly:
   ```bash
   kubectl get nodes
   ```

2. Check the status of your pods:
   ```bash
   kubectl get pods -n openedx
   ```

3. View logs for a specific pod:
   ```bash
   kubectl logs -n openedx <pod-name>
   ```

4. For more detailed troubleshooting, refer to the [Tutor Kubernetes documentation](https://docs.tutor.overhang.io/k8s.html).