#!/bin/bash

set -e


APP_NAME="flask-appconfig-demo"
AWS_REGION="eu-central-1"
TERRAFORM_DIR="./terraform"
FLASK_APP_DIR="./flask-app"


RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'


log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed. Please install it first."
        exit 1
    fi
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install it first."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log_info "Prerequisites check completed successfully."
}

deploy_infrastructure() {
    log_info "Deploying infrastructure with Terraform..."
    
    cd $TERRAFORM_DIR
    
    terraform init
    
    terraform plan
    
    terraform apply -auto-approve
    
    cd ..
    
    log_info "Infrastructure deployment completed."
}

build_and_push_docker_image() {
    log_info "Building and pushing Docker image..."
    
    ECR_REPO_URL=$(cd $TERRAFORM_DIR && terraform output -raw ecr_repository_url)
    
    log_info "ECR Repository URL: $ECR_REPO_URL"
    
    aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO_URL
    
    cd $FLASK_APP_DIR
    docker build -t $APP_NAME .
    docker tag $APP_NAME:latest $ECR_REPO_URL:latest
    
    docker push $ECR_REPO_URL:latest
    
    cd ..
    
    log_info "Docker image built and pushed successfully."
}

update_ecs_service() {
    log_info "Updating ECS service..."
    
    CLUSTER_NAME=$(cd $TERRAFORM_DIR && terraform output -raw ecs_cluster_name)
    SERVICE_NAME=$(cd $TERRAFORM_DIR && terraform output -raw ecs_service_name)
    
    aws ecs update-service \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --force-new-deployment \
        --region $AWS_REGION
    
    log_info "ECS service updated. New deployment initiated."
}

wait_for_deployment() {
    log_info "Waiting for ECS service to stabilize..."
    
    CLUSTER_NAME=$(cd $TERRAFORM_DIR && terraform output -raw ecs_cluster_name)
    SERVICE_NAME=$(cd $TERRAFORM_DIR && terraform output -raw ecs_service_name)
    
    aws ecs wait services-stable \
        --cluster $CLUSTER_NAME \
        --services $SERVICE_NAME \
        --region $AWS_REGION
    
    log_info "ECS service is now stable."
}

show_deployment_info() {
    log_info "Deployment completed successfully!"
    

    LB_URL=$(cd $TERRAFORM_DIR && terraform output -raw load_balancer_url)
    
    echo ""
    echo "==================================="
    echo "         DEPLOYMENT INFO"
    echo "==================================="
    echo "Application URL: $LB_URL"
    echo ""
    echo "Available endpoints:"
    echo "  - $LB_URL/ (home page with feature status)"
    echo "  - $LB_URL/health (health check)"
    echo "  - $LB_URL/config (current configuration)"
    echo "  - $LB_URL/users (user listing - controlled by feature flag)"
    echo ""
    echo "To test feature flag functionality:"
    echo "  1. Visit $LB_URL/users (should show 'feature disabled' message)"
    echo "  2. Go to AWS AppConfig console and update the 'featureXEnabled' flag to true"
    echo "  3. Deploy the new configuration"
    echo "  4. Wait ~30 seconds and try $LB_URL/users again"
    echo ""
    echo "CloudWatch Logs: /ecs/$APP_NAME"
    echo "==================================="
}


main() {
    log_info "Starting deployment of $APP_NAME..."
    
    check_prerequisites
    deploy_infrastructure
    build_and_push_docker_image
    update_ecs_service
    wait_for_deployment
    show_deployment_info
}


case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "destroy")
        log_warn "Destroying infrastructure..."
        cd $TERRAFORM_DIR
        terraform destroy -auto-approve
        cd ..
        log_info "Infrastructure destroyed."
        ;;
    "update-config")
        log_info "Updating AppConfig configuration..."
        echo "Please use the AWS AppConfig console to update configuration:"
        echo "1. Go to AWS AppConfig in the AWS Console"
        echo "2. Navigate to Application 'myapp' > Environment 'prod' > Configuration Profile 'app-config'"
        echo "3. Create a new hosted configuration version with updated values"
        echo "4. Deploy the new version to the 'prod' environment"
        ;;
    *)
        echo "Usage: $0 {deploy|destroy|update-config}"
        echo "  deploy       - Deploy the complete infrastructure and application"
        echo "  destroy      - Destroy all infrastructure"
        echo "  update-config- Instructions for updating AppConfig"
        exit 1
        ;;
esac
