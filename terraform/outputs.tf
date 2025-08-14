# Outputs
output "load_balancer_url" {
  description = "URL of the Application Load Balancer"
  value       = "http://${aws_lb.main.dns_name}"
}

output "ecr_repository_url" {
  description = "ECR repository URL for the Flask application"
  value       = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.app.name
}

output "appconfig_application_id" {
  description = "AppConfig application ID"
  value       = aws_appconfig_application.myapp.id
}

output "appconfig_environment_id" {
  description = "AppConfig environment ID"
  value       = aws_appconfig_environment.prod.environment_id
}

output "appconfig_configuration_profile_id" {
  description = "AppConfig configuration profile ID"
  value       = aws_appconfig_configuration_profile.appconfig.configuration_profile_id
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.app.name
}
