"""
Classify free-text user feedback into product-issue themes.

Two modes (chosen automatically):
  1. LLM mode      - if ANTHROPIC_API_KEY is set, calls the Claude API in batches.
  2. Keyword mode  - offline fallback so the project always runs (and as a baseline to compare against).

Usage:
    export ANTHROPIC_API_KEY=sk-ant-...        # optional
    python src/classify_feedback.py            # writes data/feedback_classified.csv
    python src/classify_feedback.py --mode keyword
"""
from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
MODEL = os.environ.get("CLASSIFIER_MODEL", "claude-haiku-4-5")   # change if your account uses another model name
BATCH_SIZE = 25

THEMES = {
    "slow_response":         "Complaints about speed, delays, waiting, loading",
    "misunderstood_request": "Bot did not understand the question, irrelevant or repeated answers",
    "inaccurate_answer":     "Wrong, outdated or false information",
    "cannot_perform_action": "Bot can only give instructions but cannot complete actions (refund, cancel, change plan)",
    "needs_human_agent":     "User wants a human, or escalation to an agent was hard",
    "ui_usability":          "Interface, layout, chat window, mobile or attachment problems",
    "positive_feedback":     "Praise or satisfaction",
    "other":                 "Vague, empty or does not fit any other theme",
}

SYSTEM_PROMPT = (
    "You classify short customer feedback about an AI support chatbot. "
    "Assign EXACTLY ONE theme to each item from this list:\n"
    + "\n".join(f"- {k}: {v}" for k, v in THEMES.items())
    + "\nRespond with ONLY a JSON array of objects: [{\"id\": <id>, \"theme\": \"<theme>\"}, ...]. No other text."
)

KEYWORDS = {
    "slow_response":         ["slow", "forever", "delay", "waited", "wait", "loading", "long time"],
    "misunderstood_request": ["understand", "irrelevant", "same answer", "rephrased", "nothing to do", "misunderstood"],
    "inaccurate_answer":     ["wrong", "incorrect", "outdated", "inaccurate", "false"],
    "cannot_perform_action": ["can't actually", "cannot cancel", "only tells", "no way to complete", "can't do anything", "refund"],
    "needs_human_agent":     ["human", "real person", "agent", "escalation"],
    "ui_usability":          ["window", "mobile", "buttons", "layout", "history", "screenshot", "attach"],
    "positive_feedback":     ["thanks", "helpful", "solved", "easy", "great", "perfectly", "quick"],
}


def classify_keyword(texts: list[str]) -> list[str]:
    out = []
    for t in texts:
        low = str(t).lower()
        scores = {th: sum(k in low for k in kws) for th, kws in KEYWORDS.items()}
        best = max(scores, key=scores.get)
        out.append(best if scores[best] > 0 else "other")
    return out


def classify_llm(texts: list[str]) -> list[str]:
    import anthropic  # imported lazily so keyword mode works without the package

    client = anthropic.Anthropic()
    results: list[str] = []
    for start in range(0, len(texts), BATCH_SIZE):
        chunk = texts[start:start + BATCH_SIZE]
        payload = "\n".join(f"{i}: {t}" for i, t in enumerate(chunk))
        resp = client.messages.create(
            model=MODEL, max_tokens=1500, temperature=0, system=SYSTEM_PROMPT,
            messages=[{"role": "user", "content": f"Classify these items:\n{payload}"}],
        )
        raw = "".join(b.text for b in resp.content if b.type == "text")
        raw = re.sub(r"```(?:json)?|```", "", raw).strip()
        try:
            parsed = {int(d["id"]): d["theme"] for d in json.loads(raw)}
        except (json.JSONDecodeError, KeyError, TypeError, ValueError):
            parsed = {}
        for i in range(len(chunk)):
            theme = parsed.get(i, "other")
            results.append(theme if theme in THEMES else "other")
        print(f"classified {min(start + BATCH_SIZE, len(texts))}/{len(texts)}")
    return results


def main(mode: str) -> None:
    fb = pd.read_csv(ROOT / "data" / "raw" / "feedback.csv")
    if mode == "auto":
        mode = "llm" if os.environ.get("ANTHROPIC_API_KEY") else "keyword"
    print(f"Classifier mode: {mode}  ({len(fb):,} feedback items)")
    texts = fb["feedback_text"].astype(str).tolist()
    fb["theme"] = classify_llm(texts) if mode == "llm" else classify_keyword(texts)
    fb["classifier"] = mode
    out = ROOT / "data" / "feedback_classified.csv"
    fb.to_csv(out, index=False)
    print(fb["theme"].value_counts())
    print(f"\nSaved {out}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["auto", "llm", "keyword"], default="auto")
    main(ap.parse_args().mode)
