from __future__ import annotations

import json
import os
from pathlib import PurePosixPath
from typing import Any

import boto3

from document_logic import build_bedrock_prompt, extract_line_text, parse_model_json

textract = boto3.client("textract")
bedrock = boto3.client("bedrock-runtime")
s3 = boto3.client("s3")

MODEL_ID = os.environ.get("MODEL_ID", "amazon.nova-lite-v1:0")
OUTPUT_BUCKET = os.environ["OUTPUT_BUCKET"]


def _get_textract_blocks(job_id: str) -> list[dict[str, Any]]:
    blocks: list[dict[str, Any]] = []
    token: str | None = None

    while True:
        request: dict[str, Any] = {"JobId": job_id}
        if token:
            request["NextToken"] = token

        response = textract.get_document_text_detection(**request)
        if response.get("JobStatus") != "SUCCEEDED":
            raise RuntimeError(f"Textract job is not complete: {response.get('JobStatus')}")

        blocks.extend(response.get("Blocks", []))
        token = response.get("NextToken")
        if not token:
            return blocks


def _invoke_bedrock(prompt: str) -> str:
    response = bedrock.converse(
        modelId=MODEL_ID,
        messages=[{"role": "user", "content": [{"text": prompt}]}],
        inferenceConfig={"maxTokens": 1200, "temperature": 0.1},
    )
    content = response.get("output", {}).get("message", {}).get("content", [])
    text_parts = [part.get("text", "") for part in content if part.get("text")]
    if not text_parts:
        raise RuntimeError("Bedrock returned no text content")
    return "\n".join(text_parts)


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    job_id = str(event["textract_job_id"])
    source_bucket = str(event["source_bucket"])
    source_key = str(event["source_key"])

    blocks = _get_textract_blocks(job_id)
    extracted_text = extract_line_text(blocks)
    if not extracted_text:
        raise ValueError("Textract returned no readable LINE text")

    prompt = build_bedrock_prompt(extracted_text, source_key)
    analysis = parse_model_json(_invoke_bedrock(prompt))

    source_path = PurePosixPath(source_key)
    output_key = f"processed/{source_path.stem}.json"
    result = {
        "source": {"bucket": source_bucket, "key": source_key},
        "textract_job_id": job_id,
        "model_id": MODEL_ID,
        "characters_extracted": len(extracted_text),
        **analysis,
    }

    s3.put_object(
        Bucket=OUTPUT_BUCKET,
        Key=output_key,
        Body=json.dumps(result, indent=2).encode("utf-8"),
        ContentType="application/json",
        ServerSideEncryption="AES256",
    )

    return {
        "status": "processed",
        "output_bucket": OUTPUT_BUCKET,
        "output_key": output_key,
        "document_type": result["document_type"],
        "confidence": result["confidence"],
    }
