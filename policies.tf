# Task role assume policy
data "aws_iam_policy_document" "task_assume" {
  count = "${var.create ? 1 : 0}"

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Task logging privileges
data "aws_iam_policy_document" "task_permissions" {
  count = "${var.create ? 1 : 0}"

  statement {
    effect = "Allow"

    resources = [
      "${var.create ? aws_cloudwatch_log_group.main.0.arn : ""}",
    ]

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
  }
}

# Task ecr privileges
data "aws_iam_policy_document" "task_execution_permissions" {
  count = "${var.create ? 1 : 0}"

  statement {
    effect = "Allow"

    resources = [
      "*",
    ]

    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
  }
}

# Task ssm privileges

data "aws_iam_policy_document" "task_parameter_permissions" {
  count = "${var.should_provision ? 1 : 0}"

  statement {
    effect = "Allow"

    resources = [
      "*",
    ]

    actions = [
      "ssm:GetParameters",
      "secretsmanager:GetSecretValue",
      "kms:Decrypt",
    ]
  }
}
