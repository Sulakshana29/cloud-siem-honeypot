# ─── Phase 5: Wazuh SIEM Integration ──────────────────────────────────────────
# Wazuh runs OUTSIDE AWS (Docker on your laptop), so it can't use an IAM role.
# Instead we give it a dedicated IAM user that can ONLY read the Cowrie log group.

resource "aws_iam_user" "wazuh_reader" {
  name = "wazuh-cloudwatch-reader"
  tags = { Purpose = "Wazuh SIEM pulls Cowrie logs from CloudWatch" }
}

resource "aws_iam_user_policy" "wazuh_cloudwatch_read" {
  name = "wazuh_cloudwatch_read_only"
  user = aws_iam_user.wazuh_reader.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Wazuh lists log groups to validate the config
        Sid      = "DescribeGroups"
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups"]
        Resource = "*"
      },
      {
        # Read-only access scoped to the honeypot log group
        Sid    = "ReadCowrieLogs"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogStreams",
          "logs:GetLogEvents",
          "logs:FilterLogEvents",
        ]
        Resource = [
          aws_cloudwatch_log_group.cowrie_logs.arn,
          "${aws_cloudwatch_log_group.cowrie_logs.arn}:*",
        ]
      },
    ]
  })
}

# NOTE: the secret key ends up in terraform.tfstate (which is git-ignored).
# Rotate it with `terraform apply -replace=aws_iam_access_key.wazuh_reader`.
resource "aws_iam_access_key" "wazuh_reader" {
  user = aws_iam_user.wazuh_reader.name
}

output "wazuh_access_key_id" {
  value = aws_iam_access_key.wazuh_reader.id
}

output "wazuh_secret_access_key" {
  value     = aws_iam_access_key.wazuh_reader.secret
  sensitive = true
}
