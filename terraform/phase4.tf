# ─── AWS Glue Database ──────────────────────────────────────────────────────────
resource "aws_glue_catalog_database" "siem_db" {
  name        = "cloud_siem_db"
  description = "Database for Cloud SIEM Honeypot logs"
}

# ─── AWS Glue Table (Athena Schema) ───────────────────────────────────────────
resource "aws_glue_catalog_table" "cowrie_logs" {
  name          = "cowrie_logs"
  database_name = aws_glue_catalog_database.siem_db.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"                   = "json"
    "projection.enabled"               = "true"
    "projection.year.type"             = "integer"
    "projection.year.range"            = "2024,2030"
    "projection.month.type"            = "integer"
    "projection.month.range"           = "1,12"
    "projection.month.digits"          = "2"
    "projection.day.type"              = "integer"
    "projection.day.range"             = "1,31"
    "projection.day.digits"            = "2"
    "storage.location.template"        = "s3://${aws_s3_bucket.datalake.id}/logs/year=$${year}/month=$${month}/day=$${day}/"
  }

  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.datalake.id}/logs/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "json"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
      parameters = {
        "ignore.malformed.json" = "true"
        "paths"                 = "timestamp,source,event_type,session_id,src_ip,src_port,dst_port,username,password,command,message,sensor,file_url,file_sha,file_size"
      }
    }

    columns { 
      name = "timestamp"
      type = "string" 
    }
    columns { 
      name = "source"
      type = "string" 
    }
    columns { 
      name = "event_type"
      type = "string" 
    }
    columns { 
      name = "session_id"
      type = "string" 
    }
    columns { 
      name = "src_ip"
      type = "string" 
    }
    columns { 
      name = "src_port"
      type = "int" 
    }
    columns { 
      name = "dst_port"
      type = "int" 
    }
    columns { 
      name = "username"
      type = "string" 
    }
    columns { 
      name = "password"
      type = "string" 
    }
    columns { 
      name = "command"
      type = "string" 
    }
    columns { 
      name = "message"
      type = "string" 
    }
    columns { 
      name = "sensor"
      type = "string" 
    }
    columns { 
      name = "file_url"
      type = "string" 
    }
    columns { 
      name = "file_sha"
      type = "string" 
    }
    columns { 
      name = "file_size"
      type = "string" 
    }
  }
}

# ─── Athena Workgroup ─────────────────────────────────────────────────────────
# Without a workgroup, Athena has nowhere to write query results and will fail.
resource "aws_athena_workgroup" "siem" {
  name        = "cloud-siem-workgroup"
  description = "Workgroup for Cloud SIEM honeypot threat hunting queries"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.datalake.id}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = {
    Project = "cloud-siem-honeypot"
  }
}

# ─── IAM Policy — Athena + Glue + S3 Read Access ─────────────────────────────
# Attach to any analyst IAM user/role that needs to run threat hunting queries.
resource "aws_iam_policy" "athena_analyst" {
  name        = "honeypot-athena-analyst-policy"
  description = "Allow running Athena queries against the SIEM data lake"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AthenaQueryAccess"
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:StopQueryExecution",
          "athena:ListQueryExecutions",
          "athena:GetWorkGroup"
        ]
        Resource = aws_athena_workgroup.siem.arn
      },
      {
        Sid    = "GlueCatalogRead"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetTable",
          "glue:GetPartitions",
          "glue:GetTables"
        ]
        Resource = [
          "arn:aws:glue:${var.aws_region}:*:catalog",
          aws_glue_catalog_database.siem_db.arn,
          aws_glue_catalog_table.cowrie_logs.arn
        ]
      },
      {
        Sid    = "S3DataLakeRead"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.datalake.arn,
          "${aws_s3_bucket.datalake.arn}/*"
        ]
      },
      {
        Sid    = "S3AthenaResultsWrite"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.datalake.arn}/athena-results/*"
      }
    ]
  })
}

# ─── Outputs ──────────────────────────────────────────────────────────────────
output "athena_workgroup_name" {
  value       = aws_athena_workgroup.siem.name
  description = "Use this workgroup name when running queries in the Athena console"
}
