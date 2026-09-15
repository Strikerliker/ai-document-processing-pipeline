import json
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from document_logic import build_bedrock_prompt, extract_line_text, parse_model_json


class DocumentLogicTests(unittest.TestCase):
    def test_extract_line_text_uses_only_line_blocks(self) -> None:
        blocks = [
            {"BlockType": "PAGE", "Text": "ignored"},
            {"BlockType": "LINE", "Text": "Invoice 1001"},
            {"BlockType": "LINE", "Text": "Total: $42.00"},
        ]
        self.assertEqual(extract_line_text(blocks), "Invoice 1001\nTotal: $42.00")

    def test_build_prompt_contains_source_and_text(self) -> None:
        prompt = build_bedrock_prompt("Purchase order body", "incoming/po-1.pdf")
        self.assertIn("incoming/po-1.pdf", prompt)
        self.assertIn("Purchase order body", prompt)
        self.assertIn("Return JSON only", prompt)

    def test_parse_model_json_normalizes_values(self) -> None:
        raw = json.dumps(
            {
                "document_type": "Invoice",
                "summary": "Invoice for cloud services.",
                "action_items": ["Review payment terms"],
                "confidence": 1.4,
            }
        )
        result = parse_model_json(raw)
        self.assertEqual(result["document_type"], "invoice")
        self.assertEqual(result["confidence"], 1.0)
        self.assertEqual(result["action_items"], ["Review payment terms"])

    def test_parse_model_json_handles_markdown_fence(self) -> None:
        raw = "```json\n{\"document_type\":\"contract\",\"summary\":\"Terms\",\"action_items\":[],\"confidence\":0.8}\n```"
        result = parse_model_json(raw)
        self.assertEqual(result["document_type"], "contract")
        self.assertEqual(result["summary"], "Terms")

    def test_parse_model_json_unknown_type_falls_back(self) -> None:
        raw = '{"document_type":"memo","summary":"Internal memo","action_items":[],"confidence":"bad"}'
        result = parse_model_json(raw)
        self.assertEqual(result["document_type"], "other")
        self.assertEqual(result["confidence"], 0.0)


if __name__ == "__main__":
    unittest.main()
