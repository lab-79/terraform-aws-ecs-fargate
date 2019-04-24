# ------------------------------------------------------------------------------
# Output
# ------------------------------------------------------------------------------
output "service_arn" {
  description = "The Amazon Resource Name (ARN) that identifies the service."
  value       = "${element(concat(aws_ecs_service.service.*.id, list("")), 0)}"
}

output "target_group_arn" {
  description = "The ARN of the Target Group."
  value       = "${element(concat(aws_lb_target_group.task.*.arn, list("")), 0)}"
}

output "task_role_arn" {
  description = "The Amazon Resource Name (ARN) specifying the service role."
  value       = "${element(concat(aws_iam_role.task.*.arn, list("")), 0)}"
}

output "task_execution_role_arn" {
  description = "The Amazon Resource Name (ARN) specifying the service execution role."
  value       = "${element(concat(aws_iam_role.execution.*.id, list("")), 0)}"
}

output "task_role_name" {
  description = "The name of the service role."
  value       = "${element(concat(aws_iam_role.task.*.name, list("")), 0)}"
}

output "service_sg_id" {
  description = "The Amazon Resource Name (ARN) that identifies the service security group."
  value       = "${element(concat(aws_security_group.ecs_service.*.id, list("")), 0)}"
}

output "log_group_name" {
  description = "The name of the Cloudwatch log group for the task."
  value       = "${element(concat(aws_cloudwatch_log_group.main.*.name, list("")), 0)}"
}
