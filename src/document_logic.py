from __future__ import annotations

import json
from typing import Any

ALLOWED_TYPES = {
    "invoice",
    "purchase_order",
    "contract",
    "report",
    "correspondence",
    "form",
    "other",
}


def extract_line_text(blocks: list[dict[str, Any]]) -> str:
    """Return readable text from Textract LINE blocks."""
    lines = [
        str(block.get("Text", "")).strip()
        for block in blocks
        if block.get("BlockType") == "LINE" and str(block.get("Text", "")).strip()
    ]
    return "\n".join(lines)


def build_bedrock_prompt(text: str, source_key: str) -> str:
    clipped = text[:24000]
    return f"""You are processing an enterprise document named {source_key}.
Classify the document and summarize it using only the extracted text below.

Return JSON only with this exact structure:
{{
  "document_type": "invoice|purchase_order|contract|report|correspondence|form|other",
  "summary": "concise factual summary",
  "action_items": ["action item if any"],
  "confidence": 0.0
}}

Rules:
- Do not invent information that is not present in the extracted text.
- If the document type is uncertain, use "other".
- Confidence must be a number from 0.0 to 1.0.
- If there are no action items, return an empty list.

Extracted text:
{clipped}
"""


def parse_model_json(raw_text: str) -> dict[str, Any]:
    cleaned = raw_text.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.strip("`").strip()
        if cleaned.lower().startswith("json"):
            cleaned = cleaned[4:].strip()

    data = json.loads(cleaned)
    if not isinstance(data, dict):
        raise ValueError("Model response must be a JSON object")

    document_type = str(data.get("document_type", "other")).strip().lower()
    if document_type not in ALLOWED_TYPES:
        document_type = "other"

    summary = str(data.get("summary", "")).strip()
    action_items = data.get("action_items", [])
    if not isinstance(action_items, list):
        action_items = []
    action_items = [str(item).strip() for item in action_items if str(item).strip()]

    try:
        confidence = float(data.get("confidence", 0.0))
    except (TypeError, ValueError):
        confidence = 0.0
    confidence = max(0.0, min(1.0, confidence))

    return {
        "document_type": document_type,
        "summary": summary,
        "action_items": action_items,
        "confidence": confidence,
    }
