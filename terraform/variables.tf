variable "aws_region" {
  description = "AWS Region for the document processing pipeline."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Resource-name prefix for the project."
  type        = string
  default     = "ai-document-pipeline"
}

variable "environment" {
  description = "Environment tag used for project resources."
  type        = string
  default     = "portfolio"
}

variable "bedrock_model_id" {
  description = "Amazon Bedrock model used for classification and summarization."
  type        = string
  default     = "amazon.nova-lite-v1:0"
}

variable "log_retention_days" {
  description = "CloudWatch log retention period."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Additional tags applied to supported resources."
  type        = map(string)
  default     = {}
}
