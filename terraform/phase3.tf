# ─── Random ID for Globally Unique S3 Bucket ──────────────────────────────────
resource "random_pet" "bucket_name" {
  prefix = "cloud-siem-datalake"
  length = 2
}

# ─── S3 Data Lake Bucket ──────────────────────────────────────────────────────
resource "aws_s3_bucket" "datalake" {
  bucket        = random_pet.bucket_name.id
  force_destroy = true # Allows terraform destroy even if bucket has logs
}

resource "aws_s3_bucket_server_side_encryption_configuration" "datalake_encryption" {
  bucket = aws_s3_bucket.datalake.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ─── IAM Role for Lambda ──────────────────────────────────────────────────────
resource "aws_iam_role" "lambda_exec" {
  name = "serverless_normalizer_lambda_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Allow Lambda to write to CloudWatch Logs (for its own execution logs)
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Allow Lambda to write logs to our specific S3 Data Lake
resource "aws_iam_role_policy" "lambda_s3_write" {
  name = "lambda_s3_write_policy"
  role = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["s3:PutObject"]
      Effect   = "Allow"
      Resource = "${aws_s3_bucket.datalake.arn}/*"
    }]
  })
}

# ─── Package the Python Script ────────────────────────────────────────────────
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../scripts/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

# ─── AWS Lambda Function ──────────────────────────────────────────────────────
resource "aws_lambda_function" "normalizer" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "CowrieLogNormalizer"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.10"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      S3_BUCKET_NAME = aws_s3_bucket.datalake.id
    }
  }
}

# ─── CloudWatch Trigger (Subscription Filter) ─────────────────────────────────
# 1. Give CloudWatch Logs permission to invoke our Lambda
resource "aws_lambda_permission" "cloudwatch_invoke" {
  statement_id  = "AllowCloudWatchLogsInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.normalizer.function_name
  principal     = "logs.amazonaws.com"
  source_arn    = "${aws_cloudwatch_log_group.cowrie_logs.arn}:*"
}

# 2. Tell CloudWatch to stream new logs to the Lambda
resource "aws_cloudwatch_log_subscription_filter" "cowrie_stream" {
  name            = "cowrie_lambda_trigger"
  log_group_name  = aws_cloudwatch_log_group.cowrie_logs.name
  filter_pattern  = "" # Empty means "match everything"
  destination_arn = aws_lambda_function.normalizer.arn
  
  depends_on = [aws_lambda_permission.cloudwatch_invoke]
}

# ─── Outputs ──────────────────────────────────────────────────────────────────
output "datalake_bucket_name" {
  value = aws_s3_bucket.datalake.id
}
