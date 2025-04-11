# Tutor for K3s Kubernetes Management - Ansible Edition

This repository contains Ansible playbooks and roles to set up and run [Tutor](https://docs.tutor.overhang.io/) with a K3s Kubernetes cluster deployed using the [tfgrid-k3s](https://github.com/mik-tf/tfgrid-k3s) project in the same main directory.

## Project Tree

```
.
├── tfgrid-k3s
└── tutor-k3s-ansible
```

## Overview

Tutor is the official Docker-based Open edX distribution. This setup allows you to deploy Open edX on a K3s Kubernetes cluster running on ThreeFold Grid, using Ansible for automation and configuration management instead of Bash scripts.

## Prerequisites

- A running K3s cluster deployed with the tfgrid-k3s project
- Python 3.8+ installed on your local machine
- kubectl installed on your local machine
- Ansible 2.12+ installed on your local machine
- At least 4GB of RAM and 2 CPU cores available on your K3s cluster

## Installation and Setup

### 1. Deploy K3s Cluster First

Before you can deploy Tutor, you must first have a running K3s cluster:

```bash
# Clone the tfgrid-k3s repository if you haven't already
git clone https://github.com/mik-tf/tfgrid-k3s
cd tfgrid-k3s

# Deploy the K3s cluster following instructions in tfgrid-k3s README
make
```

### 2. Clone and Set Up Tutor-K3s-Ansible

After your K3s cluster is up and running:

```bash
# Navigate back to the parent directory (where tfgrid-k3s is located)
cd ..

# Clone the tutor-k3s repository next to tfgrid-k3s
git clone https://github.com/mik-tf/tutor-k3s
cd tutor-k3s
```

### 3. Set Configuration and Environment Variables

```bash
# Docker Hub credentials (optional but recommended to avoid rate limits)
set +o history  # Disable command history for security
export DOCKER_USERNAME="your_dockerhub_username"
export DOCKER_TOKEN="your_dockerhub_token"
export DOCKER_EMAIL="your_email"
set -o history  # Re-enable command history
```

### 4. Run Setup and Deploy

```bash
# Initialize the environment and verify connection to K3s cluster
make setup

# Prepare the Kubernetes cluster for Tutor
make prepare

# Configure Docker registry authentication (if you set credentials above)
make registry-auth

# Deploy Open edX
make deploy
```

Each step performs the following functions:

**make setup**:
- Sets up KUBECONFIG to point to your tfgrid-k3s cluster's k3s.yaml file
- Creates a Python virtual environment
- Installs tutor via pip
- Tests connectivity to your K3s cluster

**make prepare**:
- Creates the necessary 'openedx' namespace
- Installs and enables required Tutor plugins (mfe, indigo, discovery, ecommerce)
- Sets up storage classes if needed
- Installs an ingress controller if not present

**make registry-auth**:
- Creates Docker registry credentials for pulling Open edX images
- Configures Kubernetes service accounts to use these credentials

**make deploy**:
- Cleans up any existing failed deployment
- Configures the Open edX platform
- Deploys all Open edX services to Kubernetes
- Waits for all pods to be ready

## Configuration

### Default Configuration
By default, the deployment will use local settings:
- LMS (Learning Management System): http://lms.local:8000
- Studio (Content Management System): http://studio.local:8001

### Customizing Configuration
You can customize your Open edX installation by modifying the configuration before deploying:

1. First, activate the environment:
```bash
# For fish shell (recommended)
source activate.fish

# For bash shell
source activate.sh
```

2. Then set your custom configuration:
```bash
# Set custom domain names
tutor config save --set LMS_HOST=your-lms-domain.com
tutor config save --set CMS_HOST=your-studio-domain.com

# Set platform name
tutor config save --set PLATFORM_NAME="Your Platform Name"

# Configure email settings
tutor config save --set EMAIL_USE_TLS=true
tutor config save --set EMAIL_HOST=smtp.your-email-provider.com

tutor config save --set EMAIL_PORT=587
tutor config save --set EMAIL_USE_SSL=false
tutor config save --set EMAIL_HOST_USER=your-email@domain.com
tutor config save --set EMAIL_HOST_PASSWORD=your-email-password

# Configure database settings
tutor config save --set MYSQL_ROOT_PASSWORD=your-secure-password
tutor config save --set MYSQL_PASSWORD=your-secure-password
```

### Common Configuration Options
Here are some commonly modified settings:

- **Platform Settings**:
  - `PLATFORM_NAME`: Name of your Open edX platform
  - `LMS_HOST`: Domain name for the LMS
  - `CMS_HOST`: Domain name for Studio
  - `ENABLE_HTTPS`: Enable HTTPS (default: false)

- **Email Settings**:
  - `EMAIL_USE_TLS`: Use TLS for email (default: true)
  - `EMAIL_HOST`: SMTP server
  - `EMAIL_PORT`: SMTP port (default: 587)
  - `EMAIL_HOST_USER`: Email username
  - `EMAIL_HOST_PASSWORD`: Email password

- **Database Settings**:
  - `MYSQL_ROOT_PASSWORD`: MySQL root password
  - `MYSQL_PASSWORD`: MySQL user password
  - `MYSQL_DATABASE`: Database name (default: edxapp)

- **Security Settings**:
  - `SECRET_KEY`: Django secret key
  - `JWT_SECRET_KEY`: JWT secret key
  - `EDXAPP_LMS_SECRET_KEY`: LMS secret key
  - `EDXAPP_CMS_SECRET_KEY`: CMS secret key

### Accessing Your Open edX Instance

After deployment, you'll need to set up access to your Open edX instance:

1. For local development, add entries to your [/etc/hosts](cci:7://file:///etc/hosts:0:0-0:0) file:
```bash
# Add to /etc/hosts
127.0.0.1 lms.local studio.local
```

2. Use port-forwarding to access the services:
```bash
# Forward LMS (Learning Management System)
kubectl port-forward -n openedx svc/lms 8000:8000

# Forward Studio (Content Management System)
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

### Troubleshooting

#### ImagePullBackOff
If you see pods stuck in `ImagePullBackOff` status:

```
NAME                     READY   STATUS             RESTARTS   AGE
cms-8697d55fc8-wddfz     0/1     ImagePullBackOff   0          17m
```

This means Kubernetes is having trouble pulling the container images. Solutions:

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
   - The `prepare` target automatically checks and attempts to increase these limits
   - You can manually increase limits by adding to `/etc/security/limits.conf` or `/etc/security/limits.d/99-openedx-limits.conf`:
     ```
     * soft nofile 65535
     * hard nofile 65535
     root soft nofile 65535
     root hard nofile 65535
     ```

#### Stuck Pods

If you have pods stuck in Terminating or other states, you can run the cleanup target:

```bash
make cleanup
```

This will force delete stuck pods and clean up resources that might be causing issues.

#### Complete Reset

If you want to completely reset your Open edX deployment:

```bash
make reset
```

Refer to the [official Tutor documentation](https://docs.tutor.overhang.io/) for more detailed instructions on using Tutor with Kubernetes.

## Ansible Structure

This project uses Ansible to organize the deployment process:

- `roles/`: Contains all the tasks for different stages of the deployment
  - `setup/`: Initial environment setup
  - `prepare/`: Preparing Kubernetes for Tutor
  - `registry/`: Docker registry authentication
  - `deploy/`: Deploying Open edX
  - `cleanup/`: Cleaning up stuck pods
  - `reset/`: Resetting the deployment
- `playbooks/`: Individual playbooks for each operation
- `group_vars/`: Common variables used across playbooks
- `inventories/`: Host definitions

## License

This project is licensed under the MIT License.
