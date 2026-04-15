# amazon-edge-demo

Demo application that converts and serves media files via containerized nginx. JPEG images are converted to WebP, AVI videos are converted to MP4. Both are served through a dark-themed HTML gallery with links to the original files.

## About

This project is a demonstration application that highlights the differences between several AWS compute deployment models. It uses a simple media gallery — converting and serving images and videos through a web browser — as a practical, visual way to show containers running across Amazon ECS with EC2 and Fargate capacity providers, as well as Amazon EKS with EC2-backed node groups and Fargate profiles.

Choosing the right compute model is one of the most consequential infrastructure decisions an organization can make, affecting cost, operational overhead, and scalability. Rather than comparing these options in the abstract, this demo puts them side by side with identical workloads so that the differences in deployment, networking, and access patterns become tangible. Each container operates independently with no network communication between them, which is intentional — these types of deployments don't require inter-container coordination, and keeping them isolated is simply easier to operate.

The demo is packaged as two lightweight containers — one for images, one for videos — each built on nginx and responsible for converting source media files at startup before serving them through a dark-themed gallery page. Infrastructure is provisioned with Terraform, which stands up a VPC, EKS cluster, and ECS cluster in a single apply. Kubernetes deployments are managed with Kustomize overlays that target either EC2 or Fargate environments. A local testing script is included so the full experience can be previewed on a laptop with nothing more than Docker installed.

## Containers

| Image | Description | Registry |
|-------|-------------|----------|
| `amazon-edge-demo-images` | Converts JPEGs to WebP at startup, serves image gallery | `ghcr.io/pelotech/amazon-edge-demo-images` |
| `amazon-edge-demo-videos` | Converts AVIs to MP4 at startup, serves video gallery | `ghcr.io/pelotech/amazon-edge-demo-videos` |

Both containers expose port 80 and generate an `index.html` gallery page with links to converted and original files.

## Architecture

See [docs/architecture.md](docs/architecture.md) for the full infrastructure diagram, subnet placement details, and demo access credentials.

### ECS (AWS)

- **3 images containers** on EC2 capacity provider
- **1 video container** on Fargate capacity provider
- All services accessible on **port 80** via public IP

### EKS (AWS)

- **3 images containers** + **1 video container** on EC2-backed managed node groups (t3a.small)
  - Images pods use pod anti-affinity to spread across different nodes
  - Accessible via NodePort on the node's public IP:
    - Images: `http://<node-ip>:30080`
    - Videos: `http://<node-ip>:30081`
- **1 images container** + **1 video container** on Fargate (namespace: `fargate`)
  - Fargate pods require **`kubectl port-forward`** to access:
    ```bash
    kubectl port-forward -n fargate svc/amazon-edge-images 8080:80
    kubectl port-forward -n fargate svc/amazon-edge-videos 8081:80
    ```

## Local Testing

```bash
./test-local.sh
```

Builds both containers and runs them locally:
- Images gallery: http://localhost:8080
- Videos gallery: http://localhost:8081

Stop with: `docker rm -f amazon-edge-images amazon-edge-videos`

## Publishing

Images are published to GHCR via manual workflow dispatch:

```bash
gh workflow run publish.yml
```

Tags: `latest` + `sha-<short commit hash>`

## Project Structure

```
.
├── Dockerfile.images          # nginx + libwebp-tools
├── Dockerfile.videos          # nginx + ffmpeg
├── entrypoint-images.sh       # JPEG -> WebP conversion + gallery generation
├── entrypoint-videos.sh       # AVI -> MP4 conversion + gallery generation
├── nginx.conf                 # Static file serving + /originals/ autoindex
├── test-local.sh              # Local build and run script
├── images/                    # Source JPEG files (10 samples)
├── videos/                    # Source AVI files (5 samples)
├── .github/workflows/
│   └── publish.yml            # Manual GHCR publish workflow
├── kustomize/
│   ├── ec2/                   # EKS EC2 node group deployments
│   └── fargate/               # EKS Fargate namespace deployments
└── terraform/
    └── main.tf                # VPC, EKS, ECS infrastructure
```

## Deploying

### Kustomize (EKS)

```bash
# EC2 node group (3 images + 1 video)
kubectl apply -k kustomize/ec2/

# Fargate (1 images + 1 video in fargate namespace)
kubectl apply -k kustomize/fargate/
```

### Terraform (ECS + EKS)

```bash
cd terraform
terraform init
terraform apply
```

Provisions VPC, EKS cluster with EC2 nodes and Fargate profile, and ECS cluster with EC2 capacity provider.
