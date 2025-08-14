# Flask AppConfig ECS Deployment Guide

This guide demonstrates how to deploy a simple Flask application on Amazon ECS that uses AWS AppConfig to dynamically control feature flags without requiring application restarts.

## Architecture Overview

The solution includes:
- **Flask Application**: A simple web app with a user listing feature controlled by AppConfig
- **AWS AppConfig**: Dynamic configuration management with feature flags
- **Amazon ECS**: Container orchestration with Fargate
- **AppConfig Agent**: Sidecar container for efficient configuration retrieval
- **Application Load Balancer**: Public access to the application
- **Amazon ECR**: Container image registry

## Prerequisites

Before deploying, ensure you have:
- AWS CLI installed and configured with appropriate permissions
- Terraform >= 1.0
- Docker installed and running
- An AWS account with sufficient permissions for ECS, AppConfig, ECR, ALB, and IAM

## Project Structure

```
Research/
├── flask-app/
│   ├── app.py              # Main Flask application
│   ├── requirements.txt    # Python dependencies
│   └── Dockerfile         # Container configuration
├── terraform/
│   ├── main.tf            # Infrastructure as code
│   └── outputs.tf         # Terraform outputs
├── deploy.sh              # Deployment automation script
└── DEPLOYMENT.md          # This file
```

## Quick Start

1. **Clone and navigate to the project:**
   ```bash
   cd /Users/hassan/Documents/Projects/DevSecOps/Research
   ```

2. **Deploy everything with one command:**
   ```bash
   ./deploy.sh deploy
   ```

3. **Access your application:**
   The script will output the Application Load Balancer URL when deployment is complete.

## Manual Deployment Steps

If you prefer to deploy manually:

### Step 1: Deploy Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### Step 2: Build and Push Docker Image

```bash
# Get ECR repository URL from Terraform output
ECR_REPO=$(terraform output -raw ecr_repository_url)

# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_REPO

# Build and push image
cd ../flask-app
docker build -t flask-appconfig-demo .
docker tag flask-appconfig-demo:latest $ECR_REPO:latest
docker push $ECR_REPO:latest
```

### Step 3: Update ECS Service

```bash
cd ../terraform
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
SERVICE_NAME=$(terraform output -raw ecs_service_name)

aws ecs update-service \
  --cluster $CLUSTER_NAME \
  --service $SERVICE_NAME \
  --force-new-deployment \
  --region us-east-1
```

## Testing the Feature Flag

1. **Initial State**: Visit `/users` endpoint - should show "feature disabled" message
2. **Enable Feature**: 
   - Go to AWS AppConfig console
   - Navigate to Application 'myapp' → Environment 'prod' → Configuration Profile 'app-config'
   - Create new configuration version with `"featureXEnabled": true`
   - Deploy the new version
3. **Verify Change**: Wait ~30 seconds, then visit `/users` again - should now show user list

## Application Endpoints

- `/` - Home page showing current configuration and feature status
- `/health` - Health check endpoint
- `/config` - Current configuration as JSON
- `/users` - User listing (controlled by `featureXEnabled` flag)

## Configuration Management

The AppConfig configuration contains:
```json
{
  "featureXEnabled": false,    // Controls user listing feature
  "apiUrl": "https://api.example.com",
  "maxUsers": 100,
  "debugMode": false
}
```

## Monitoring and Logs

- **CloudWatch Logs**: `/ecs/flask-appconfig-demo`
- **Application Metrics**: Available via the `/health` endpoint
- **ECS Service**: Monitor via ECS console for task health and deployments

## Architecture Details

### ECS Task Configuration

The ECS task runs two containers:
1. **AppConfig Agent** (`public.ecr.aws/aws-appconfig/aws-appconfig-agent:2.x`)
   - Polls AppConfig every 45 seconds
   - Caches configuration locally
   - Serves config via HTTP on port 2772

2. **Flask Application** (custom image in ECR)
   - Depends on AppConfig agent health
   - Retrieves config from agent via localhost:2772
   - Updates configuration every 30 seconds in background

### Security

- ECS tasks use IAM roles with minimal required permissions
- AppConfig agent communication is over localhost only
- Application runs as non-root user
- Security groups restrict traffic appropriately

### High Availability

- ECS service runs 2 tasks across multiple AZs
- Application Load Balancer distributes traffic
- Health checks ensure only healthy containers receive traffic
- Auto-recovery if tasks fail

## Cost Considerations

- **ECS Fargate**: ~$30-50/month for 2 tasks (0.25 vCPU, 0.5 GB RAM each)
- **Application Load Balancer**: ~$16/month + data processing charges
- **AppConfig**: Minimal cost (~$0.50/month for typical usage)
- **ECR**: Storage costs for container images
- **CloudWatch Logs**: Based on log volume

## Cleanup

To destroy all resources:
```bash
./deploy.sh destroy
```

Or manually:
```bash
cd terraform
terraform destroy
```

## Troubleshooting

### Common Issues

1. **503 Service Unavailable**
   - Check ECS service status
   - Verify target group health
   - Check CloudWatch logs for errors

2. **Config Not Updating**
   - Verify AppConfig deployment completed
   - Check agent logs in CloudWatch
   - Ensure task has proper IAM permissions

3. **Container Won't Start**
   - Check ECR image exists and is accessible
   - Verify task role permissions
   - Review container logs in ECS console

### Useful Commands

```bash
# Check ECS service status
aws ecs describe-services --cluster flask-appconfig-demo --services flask-appconfig-demo

# View latest logs
aws logs tail /ecs/flask-appconfig-demo --follow

# Check AppConfig deployment
aws appconfig list-deployments --application-id myapp --environment-id prod
```

## Security Best Practices

- Use AWS Secrets Manager for sensitive configuration
- Implement least-privilege IAM policies
- Enable VPC Flow Logs for network monitoring
- Use AWS Config for compliance monitoring
- Enable AWS CloudTrail for API auditing
