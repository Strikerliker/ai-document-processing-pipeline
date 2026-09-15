# Deployment Guide

## Prerequisites

- Terraform 1.6 or later
- AWS CLI or another approved AWS authentication method
- An AWS account where you are authorized to create S3, IAM, Lambda, Step Functions, EventBridge, Textract, CloudWatch, and Bedrock resources
- Access to the configured Amazon Bedrock model in the selected Region

## Validate locally

```bash
python -m unittest discover -s tests -v
cd terraform
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

## Plan

```bash
cd terraform
terraform init
terraform plan -out=tfplan
```

Review the plan for:

- input and output S3 bucket names
- IAM role permissions
- Step Functions workflow definition
- Lambda environment variables
- EventBridge trigger configuration
- selected Bedrock model ID

## Apply

```bash
terraform apply tfplan
```

## Test the pipeline

After apply completes, retrieve the input and output bucket names:

```bash
terraform output input_bucket_name
terraform output output_bucket_name
```

Upload a PDF or image supported by Textract:

```bash
aws s3 cp sample.pdf s3://YOUR_INPUT_BUCKET/incoming/sample.pdf
```

The S3 event should start the Step Functions state machine automatically. When processing succeeds, the output bucket will contain:

```text
processed/sample.json
```

## Result format

The output JSON includes:

- source S3 bucket and key
- Textract job ID
- Bedrock model ID
- number of extracted characters
- normalized document type
- factual summary
- action items
- confidence score

## Operational notes

- Textract and Bedrock usage can incur charges.
- Model availability varies by Region and account access.
- The sample prompt limits the text sent to Bedrock to 24,000 characters.
- For larger production workloads, use chunking, queueing, retries, and explicit quotas.
- Keep Terraform state in a protected remote backend for real environments.

## Destroy

```bash
terraform destroy
```

S3 buckets containing objects may need their contents removed before destruction. Preserve any documents or processed results required by your retention policy before deleting the stack.
