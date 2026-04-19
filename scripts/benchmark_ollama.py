#!/usr/bin/env python3
"""
Ollama model benchmark — measures tokens/sec and latency for three tasks:
chat, summarization, and memory extraction.

Requires Ollama to be running (default: http://localhost:11434).
Models that are not pulled are skipped with a hint.

Usage:
    python scripts/benchmark_ollama.py
    python scripts/benchmark_ollama.py --models qwen2.5 llama3.2
    python scripts/benchmark_ollama.py --url http://localhost:11434 --tasks chat summarize
"""

import argparse
import json
import sys
import time
import urllib.request
from typing import Any

DEFAULT_URL = "http://localhost:11434"
DEFAULT_MODELS = ["qwen2.5", "llama3.2", "mistral"]

TASKS: dict[str, dict[str, str]] = {
    "chat": {
        "system": "You are a helpful assistant.",
        "user": "Tell me one interesting fact about the Roman Empire in a single sentence.",
    },
    "summarize": {
        "system": "Summarize the following passage in a single sentence.",
        "user": (
            "The Apollo 11 mission, launched on July 16 1969, carried astronauts Neil Armstrong, "
            "Buzz Aldrin, and Michael Collins to the Moon. Armstrong and Aldrin became the first "
            "humans to walk on the lunar surface on July 20, while Collins orbited above. "
            "The mission fulfilled President Kennedy's 1961 goal of landing a man on the Moon "
            "before the end of the decade and was a landmark achievement in the Space Race."
        ),
    },
    "memory_extract": {
        "system": (
            "Extract key facts from the user's statement. "
            "Reply with a JSON array of short strings. No prose."
        ),
        "user": (
            "I had a meeting with Alice at 2 pm about the Q3 budget. "
            "We decided to cut travel expenses by 20% and defer the new hire until January."
        ),
    },
}


def _ollama_get(url: str, path: str, timeout: int = 10) -> Any:
    with urllib.request.urlopen(f"{url}{path}", timeout=timeout) as resp:
        return json.loads(resp.read())


def available_models(url: str) -> set[str]:
    try:
        data = _ollama_get(url, "/api/tags")
        return {m["name"].split(":")[0] for m in data.get("models", [])}
    except Exception:
        return set()


def generate(url: str, model: str, task: dict[str, str]) -> dict[str, Any]:
    payload = json.dumps({
        "model": model,
        "messages": [
            {"role": "system", "content": task["system"]},
            {"role": "user", "content": task["user"]},
        ],
        "stream": False,
        "options": {"num_predict": 256},
    }).encode()

    req = urllib.request.Request(
        f"{url}/api/chat",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    t0 = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            raw = resp.read()
    except Exception as exc:
        return {"error": str(exc)}
    elapsed_s = time.perf_counter() - t0

    data = json.loads(raw)
    content: str = data.get("message", {}).get("content", "").strip()
    eval_count: int = data.get("eval_count", 0)
    eval_duration_ns: int = data.get("eval_duration", 1) or 1
    tps = eval_count / (eval_duration_ns / 1e9)

    return {
        "elapsed_s": round(elapsed_s, 2),
        "tokens": eval_count,
        "tps": round(tps, 1),
        "output": (content[:100] + "…") if len(content) > 100 else content,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Benchmark Ollama models")
    parser.add_argument("--url", default=DEFAULT_URL, help="Ollama base URL")
    parser.add_argument("--models", nargs="+", default=DEFAULT_MODELS)
    parser.add_argument(
        "--tasks", nargs="+", default=list(TASKS.keys()),
        choices=list(TASKS.keys()), metavar="TASK",
    )
    args = parser.parse_args()

    try:
        _ollama_get(args.url, "/api/tags", timeout=5)
    except Exception:
        sys.exit(f"ERROR: Cannot reach Ollama at {args.url}. Start it with: ollama serve")

    pulled = available_models(args.url)
    print(f"Ollama: {args.url}  |  pulled models: {', '.join(sorted(pulled)) or 'none'}\n")

    for task_name in args.tasks:
        task = TASKS[task_name]
        prompt_preview = task["user"][:80] + ("…" if len(task["user"]) > 80 else "")
        print(f"Task: {task_name}")
        print(f"  Prompt: {prompt_preview}")
        print(f"  {'Model':<22} {'Time (s)':<12} {'Tokens':<10} {'Tok/s':<10} Output")
        print("  " + "-" * 100)

        for model in args.models:
            if model.split(":")[0] not in pulled:
                print(f"  {model:<22} SKIPPED — run: ollama pull {model}")
                continue

            print(f"  {model:<22} …", end="\r", flush=True)
            res = generate(args.url, model, task)
            if "error" in res:
                print(f"  {model:<22} ERROR: {res['error']}")
            else:
                print(
                    f"  {model:<22} {res['elapsed_s']:<12} {res['tokens']:<10} "
                    f"{res['tps']:<10} {res['output']}"
                )
        print()

    print("Tok/s = tokens generated per second (higher is better).")
    print("Time includes first-token latency (model loading is amortised after first call).")


if __name__ == "__main__":
    main()
