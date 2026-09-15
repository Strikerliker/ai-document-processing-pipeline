# Architecture and Security Design

## Objective

Provide a serverless AWS reference architecture that turns uploaded documents into structured, AI-enriched JSON without exposing storage publicly or relying on long-lived credentials.

## Logical flow

1. **Amazon S3 input bucket** receives a source document.
2. **Amazon EventBridge** receives the S3 object-created event.
3. **AWS Step Functions** starts and monitors asynchronous text extraction.
4. **Amazon Textract** extracts readable LINE blocks from the document.
5. **AWS Lambda** collects the completed Textract result, constructs a constrained prompt, and invokes Amazon Bedrock.
6. **Amazon Bedrock** returns document type, summary, action items, and confidence.
7. **AWS Lambda** validates and normalizes the model output before writing JSON to the output S3 bucket.
8. **Amazon CloudWatch Logs** captures Lambda and workflow errors for troubleshooting.

## Security design decisions

### Separate input and output buckets

Source documents and AI-produced results are stored separately. Both buckets have versioning, server-side encryption, and S3 Block Public Access enabled.

### Least-privilege service roles

- EventBridge can only start the project state machine.
- Step Functions can read incoming documents, call Textract, invoke the processor Lambda, and publish workflow logs.
- Lambda can retrieve Textract results, invoke Bedrock, write beneath the output bucket's `processed/` prefix, and write its own CloudWatch logs.

### Grounded processing

The Bedrock prompt explicitly instructs the model to use only text extracted from the source document and to return a constrained JSON schema. The Lambda code parses and normalizes the returned JSON before storing it.

### Manual deployment

The repository validates infrastructure automatically but does not auto-apply Terraform. This avoids creating billable resources or modifying an AWS account without an explicit deployment decision.

## Failure handling

The Step Functions workflow polls Textract until the job succeeds or fails. Failed Textract jobs terminate in a dedicated failure state rather than being passed to the AI processing step.

## Production extension path

A production implementation could add:

- KMS customer-managed keys
- malware scanning before Textract
- Amazon Macie classification
- SQS dead-letter queues for failed events
- private VPC endpoints where appropriate
- document-level retention policies
- human approval for low-confidence classifications
- Step Functions retry/catch policies with alerting
- Amazon OpenSearch or a vector store for downstream search
- DynamoDB metadata and workflow status tracking
- API Gateway or an application UI for uploads and result review
