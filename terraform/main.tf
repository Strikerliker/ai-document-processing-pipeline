data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Portfolio   = "John-D"
    },
    var.tags
  )
}

resource "aws_s3_bucket" "input" {
  bucket = "${local.name_prefix}-${data.aws_caller_identity.current.account_id}-input"
}

resource "aws_s3_bucket" "output" {
  bucket = "${local.name_prefix}-${data.aws_caller_identity.current.account_id}-output"
}

resource "aws_s3_bucket_public_access_block" "input" {
  bucket = aws_s3_bucket.input.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "output" {
  bucket = aws_s3_bucket.output.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "input" {
  bucket = aws_s3_bucket.input.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "output" {
  bucket = aws_s3_bucket.output.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "input" {
  bucket = aws_s3_bucket.input.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "output" {
  bucket = aws_s3_bucket.output.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_notification" "input_events" {
  bucket      = aws_s3_bucket.input.id
  eventbridge = true
}

data "archive_file" "processor" {
  type        = "zip"
  source_dir  = "${path.module}/../src"
  output_path = "${path.module}/processor.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "processor" {
  name               = "${local.name_prefix}-processor-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "processor_logs" {
  role       = aws_iam_role.processor.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "processor" {
  statement {
    sid       = "ReadTextractResults"
    effect    = "Allow"
    actions   = ["textract:GetDocumentTextDetection"]
    resources = ["*"]
  }

  statement {
    sid       = "InvokeBedrockModel"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel"]
    resources = ["*"]
  }

  statement {
    sid       = "WriteProcessedResults"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.output.arn}/processed/*"]
  }
}

resource "aws_iam_role_policy" "processor" {
  name   = "${local.name_prefix}-processor-policy"
  role   = aws_iam_role.processor.id
  policy = data.aws_iam_policy_document.processor.json
}

resource "aws_cloudwatch_log_group" "processor" {
  name              = "/aws/lambda/${local.name_prefix}-processor"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "processor" {
  function_name = "${local.name_prefix}-processor"
  role          = aws_iam_role.processor.arn
  runtime       = "python3.12"
  handler       = "processor.lambda_handler"
  timeout       = 120
  memory_size   = 512

  filename         = data.archive_file.processor.output_path
  source_code_hash = data.archive_file.processor.output_base64sha256

  environment {
    variables = {
      MODEL_ID      = var.bedrock_model_id
      OUTPUT_BUCKET = aws_s3_bucket.output.id
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.processor,
    aws_iam_role_policy_attachment.processor_logs,
    aws_iam_role_policy.processor
  ]
}

data "aws_iam_policy_document" "states_assume" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "states" {
  name               = "${local.name_prefix}-states-role"
  assume_role_policy = data.aws_iam_policy_document.states_assume.json
}

data "aws_iam_policy_document" "states" {
  statement {
    sid       = "ReadIncomingDocuments"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.input.arn}/*"]
  }

  statement {
    sid = "RunTextract"
    effect = "Allow"
    actions = [
      "textract:StartDocumentTextDetection",
      "textract:GetDocumentTextDetection"
    ]
    resources = ["*"]
  }

  statement {
    sid       = "InvokeProcessor"
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.processor.arn]
  }

  statement {
    sid    = "WorkflowLogging"
    effect = "Allow"
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "states" {
  name   = "${local.name_prefix}-states-policy"
  role   = aws_iam_role.states.id
  policy = data.aws_iam_policy_document.states.json
}

resource "aws_cloudwatch_log_group" "workflow" {
  name              = "/aws/vendedlogs/states/${local.name_prefix}"
  retention_in_days = var.log_retention_days
}

resource "aws_sfn_state_machine" "pipeline" {
  name     = "${local.name_prefix}-workflow"
  role_arn = aws_iam_role.states.arn

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.workflow.arn}:*"
    include_execution_data = false
    level                  = "ERROR"
  }

  definition = jsonencode({
    Comment = "Extract document text with Textract, then classify and summarize it with Bedrock."
    StartAt = "StartTextract"
    States = {
      StartTextract = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:textract:startDocumentTextDetection"
        Parameters = {
          DocumentLocation = {
            S3Object = {
              "Bucket.$" = "$.detail.bucket.name"
              "Name.$"   = "$.detail.object.key"
            }
          }
        }
        ResultPath = "$.textractStart"
        Next       = "WaitForTextract"
      }
      WaitForTextract = {
        Type    = "Wait"
        Seconds = 5
        Next    = "CheckTextract"
      }
      CheckTextract = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:textract:getDocumentTextDetection"
        Parameters = {
          "JobId.$" = "$.textractStart.JobId"
        }
        ResultPath = "$.textractStatus"
        Next       = "TextractComplete"
      }
      TextractComplete = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.textractStatus.JobStatus"
            StringEquals = "SUCCEEDED"
            Next         = "ProcessDocument"
          },
          {
            Variable     = "$.textractStatus.JobStatus"
            StringEquals = "FAILED"
            Next         = "TextractFailed"
          }
        ]
        Default = "WaitForTextract"
      }
      ProcessDocument = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.processor.arn
          Payload = {
            "textract_job_id.$" = "$.textractStart.JobId"
            "source_bucket.$"   = "$.detail.bucket.name"
            "source_key.$"      = "$.detail.object.key"
          }
        }
        End = true
      }
      TextractFailed = {
        Type  = "Fail"
        Error = "TextractJobFailed"
        Cause = "Amazon Textract failed to process the uploaded document."
      }
    }
  })
}

data "aws_iam_policy_document" "events_assume" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "events" {
  name               = "${local.name_prefix}-events-role"
  assume_role_policy = data.aws_iam_policy_document.events_assume.json
}

data "aws_iam_policy_document" "events" {
  statement {
    effect    = "Allow"
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.pipeline.arn]
  }
}

resource "aws_iam_role_policy" "events" {
  name   = "${local.name_prefix}-events-policy"
  role   = aws_iam_role.events.id
  policy = data.aws_iam_policy_document.events.json
}

resource "aws_cloudwatch_event_rule" "documents" {
  name        = "${local.name_prefix}-documents"
  description = "Start the AI document workflow when an object is created in the input bucket."

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.input.id]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "documents" {
  rule     = aws_cloudwatch_event_rule.documents.name
  arn      = aws_sfn_state_machine.pipeline.arn
  role_arn = aws_iam_role.events.arn
}
