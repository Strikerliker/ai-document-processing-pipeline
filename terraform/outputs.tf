output "input_bucket_name" {
  description = "S3 bucket where source documents are uploaded."
  value       = aws_s3_bucket.input.id
}

output "output_bucket_name" {
  description = "S3 bucket that stores processed JSON results."
  value       = aws_s3_bucket.output.id
}

output "state_machine_arn" {
  description = "Step Functions state machine ARN."
  value       = aws_sfn_state_machine.pipeline.arn
}

output "processor_lambda_name" {
  description = "Lambda function that classifies and summarizes extracted text."
  value       = aws_lambda_function.processor.function_name
}

output "eventbridge_rule_name" {
  description = "EventBridge rule that starts document processing."
  value       = aws_cloudwatch_event_rule.documents.name
}
