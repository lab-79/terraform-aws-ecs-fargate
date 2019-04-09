# ------------------------------------------------------------------------------
# AWS
# ------------------------------------------------------------------------------
data "aws_region" "current" {}

# ------------------------------------------------------------------------------
# Cloudwatch
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "main" {
  count             = "${var.create ? 1 : 0}"
  name              = "${var.name_prefix}"
  retention_in_days = "${var.log_retention_in_days}"
  tags              = "${var.tags}"
}

# ------------------------------------------------------------------------------
# IAM - Task execution role, needed to pull ECR images etc.
# ------------------------------------------------------------------------------
resource "aws_iam_role" "execution" {
  count              = "${var.create ? 1 : 0}"
  name               = "${var.name_prefix}-task-execution-role"
  assume_role_policy = "${element(concat(data.aws_iam_policy_document.task_assume.*.json, list("")), 0)}"
}

resource "aws_iam_role_policy" "task_execution" {
  count  = "${var.create ? 1 : 0}"
  name   = "${var.name_prefix}-task-execution"
  role   = "${element(concat(aws_iam_role.execution.*.id, list("")), 0)}"
  policy = "${element(concat(data.aws_iam_policy_document.task_execution_permissions.*.json, list("")), 0)}"
}

# ------------------------------------------------------------------------------
# IAM - Task role, basic. Users of the module will append policies to this role
# when they use the module. S3, Dynamo permissions etc etc.
# ------------------------------------------------------------------------------
resource "aws_iam_role" "task" {
  count              = "${var.create ? 1 : 0}"
  name               = "${var.name_prefix}-task-role"
  assume_role_policy = "${element(concat(data.aws_iam_policy_document.task_assume.*.json, list("")), 0)}"
}

resource "aws_iam_role_policy" "log_agent" {
  count  = "${var.create ? 1 : 0}"
  name   = "${var.name_prefix}-log-permissions"
  role   = "${element(concat(aws_iam_role.task.*.id, list("")), 0)}"
  policy = "${element(concat(data.aws_iam_policy_document.task_permissions.*.json, list("")), 0)}"
}

# ------------------------------------------------------------------------------
# Security groups
# ------------------------------------------------------------------------------
resource "aws_security_group" "ecs_service" {
  count       = "${var.create ? 1 : 0}"
  vpc_id      = "${var.vpc_id}"
  name        = "${var.name_prefix}-ecs-service-sg"
  description = "Fargate service security group"
  tags        = "${merge(var.tags, map("Name", "${var.name_prefix}-sg"))}"
}

resource "aws_security_group_rule" "egress_service" {
  count             = "${var.create ? 1 : 0}"
  security_group_id = "${element(concat(aws_security_group.ecs_service.*.id, list("")), 0)}"
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
}

# ------------------------------------------------------------------------------
# LB Target group
# ------------------------------------------------------------------------------
resource "aws_lb_target_group" "task" {
  count        = "${var.create ? 1 : 0}"
  vpc_id       = "${var.vpc_id}"
  protocol     = "${var.task_container_protocol}"
  port         = "${var.task_container_port}"
  target_type  = "ip"
  health_check = ["${var.health_check}"]

  # NOTE: TF is unable to destroy a target group while a listener is attached,
  # therefor we have to create a new one before destroying the old. This also means
  # we have to let it have a random name, and then tag it with the desired name.
  lifecycle {
    create_before_destroy = true
  }

  tags = "${merge(var.tags, map("Name", "${var.name_prefix}-target-${var.task_container_port}"))}"
}

# ------------------------------------------------------------------------------
# ECS Task/Service
# ------------------------------------------------------------------------------
data "null_data_source" "task_environment" {
  count = "${var.create * var.task_container_environment_count}"

  inputs = {
    name  = "${element(keys(var.task_container_environment), count.index)}"
    value = "${element(values(var.task_container_environment), count.index)}"
  }
}

data "null_data_source" "task_environment_secret" {
  count = "${var.task_container_environment_secret_count}"

  inputs = {
    name      = "${element(keys(var.task_container_environment_secret), count.index)}"
    valueFrom = "${element(values(var.task_container_environment_secret), count.index)}"
  }
}
resource "aws_ecs_task_definition" "task" {
  count                    = "${var.create ? 1 : 0}"
  family                   = "${var.name_prefix}"
  execution_role_arn       = "${element(concat(aws_iam_role.execution.*.arn, list("")), 0)}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "${var.task_definition_cpu}"
  memory                   = "${var.task_definition_memory}"
  task_role_arn            = "${element(concat(aws_iam_role.task.*.arn, list("")), 0)}"

  container_definitions = <<EOF
[{
    "name": "${var.name_prefix}",
    "image": "${var.task_container_image}",
    "essential": true,
    "portMappings": [
        {
            "containerPort": ${var.task_container_port},
            "hostPort": ${var.task_container_port},
            "protocol":"tcp"
        }
    ],
    "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
            "awslogs-group": "${element(concat(aws_cloudwatch_log_group.main.*.name, list("")), 0)}",
            "awslogs-region": "${element(concat(data.aws_region.current.*.name, list("")), 0)}",
            "awslogs-stream-prefix": "container"
        }
    },
    "command": ${jsonencode(var.task_container_command)},
    "environment": ${jsonencode(data.null_data_source.task_environment.*.outputs)},
    "secrets": ${jsonencode(data.null_data_source.task_environment_secret.*.outputs)}
}]
EOF
}

resource "aws_ecs_service" "service" {
  count                              = "${var.create ? 1 : 0}"
  depends_on                         = ["null_resource.lb_exists"]
  name                               = "${var.name_prefix}"
  cluster                            = "${var.cluster_id}"
  task_definition                    = "${element(concat(aws_ecs_task_definition.task.*.arn, list("")), 0)}"
  desired_count                      = "${var.desired_count}"
  launch_type                        = "FARGATE"
  deployment_minimum_healthy_percent = "${var.deployment_minimum_healthy_percent}"
  deployment_maximum_percent         = "${var.deployment_maximum_percent}"
  health_check_grace_period_seconds  = "${var.health_check_grace_period_seconds}"

  network_configuration {
    subnets         = ["${var.private_subnet_ids}"]
    security_groups = ["${compact(concat(aws_security_group.ecs_service.*.id, var.extra_security_groups))}"]

    assign_public_ip = "${var.task_container_assign_public_ip}"
  }

  load_balancer {
    container_name   = "${var.name_prefix}"
    container_port   = "${var.task_container_port}"
    target_group_arn = "${element(concat(aws_lb_target_group.task.*.arn, list("")), 0)}"
  }
}

# HACK: The workaround used in ecs/service does not work for some reason in this module, this fixes the following error:
# "The target group with targetGroupArn arn:aws:elasticloadbalancing:... does not have an associated load balancer."
# see https://github.com/hashicorp/terraform/issues/12634.
# Service depends on this resources which prevents it from being created until the LB is ready
resource "null_resource" "lb_exists" {
  count = "${var.create ? 1 : 0}"

  triggers {
    alb_name = "${var.lb_arn}"
  }
}
