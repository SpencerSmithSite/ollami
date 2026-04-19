import json
from datetime import datetime, timezone

from database.db import SessionLocal
from database.models import Conversation, Memory, User
from utils.llm.ollama_client import chat_model, get_ollama
from utils.memory.chroma_store import search_memories as chroma_search
from utils.memory.chroma_store import upsert_memory

_LOCAL_USER_ID = "local"

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "search_memories",
            "description": "Search the user's saved memories using semantic similarity.",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Search query"},
                    "n_results": {"type": "integer", "description": "Number of results (default 5)"},
                },
                "required": ["query"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "create_memory",
            "description": "Save a new memory for the user.",
            "parameters": {
                "type": "object",
                "properties": {
                    "content": {"type": "string", "description": "The content to remember"},
                },
                "required": ["content"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_current_time",
            "description": "Get the current date and time in ISO 8601 format.",
            "parameters": {"type": "object", "properties": {}},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "list_recent_conversations",
            "description": "List the user's most recent recorded conversations.",
            "parameters": {
                "type": "object",
                "properties": {
                    "limit": {"type": "integer", "description": "Max conversations to return (default 5)"},
                },
            },
        },
    },
]


async def _exec_search_memories(args: dict) -> str:
    hits = await chroma_search(args.get("query", ""), args.get("n_results", 5))
    if not hits:
        return "No memories found."
    lines = [f"- [{h['id']}] {h['content']} (distance: {h['distance']:.3f})" for h in hits]
    return "\n".join(lines)


async def _exec_create_memory(args: dict) -> str:
    content = args.get("content", "").strip()
    if not content:
        return "Error: content is required."
    db = SessionLocal()
    try:
        user = db.get(User, _LOCAL_USER_ID)
        if user is None:
            user = User(id=_LOCAL_USER_ID, name="Local User")
            db.add(user)
            db.commit()
        m = Memory(user_id=_LOCAL_USER_ID, content=content)
        db.add(m)
        db.commit()
        db.refresh(m)
        m.embedding_id = m.id
        await upsert_memory(m.id, content)
        db.commit()
        return f"Memory saved (id={m.id})."
    finally:
        db.close()


def _exec_get_current_time(_args: dict) -> str:
    return datetime.now(timezone.utc).isoformat()


def _exec_list_recent_conversations(args: dict) -> str:
    limit = int(args.get("limit", 5))
    db = SessionLocal()
    try:
        convs = (
            db.query(Conversation)
            .filter(Conversation.user_id == _LOCAL_USER_ID)
            .order_by(Conversation.created_at.desc())
            .limit(limit)
            .all()
        )
        if not convs:
            return "No conversations found."
        lines = [f"- [{c.id}] {c.title or '(untitled)'} at {c.created_at.isoformat()}" for c in convs]
        return "\n".join(lines)
    finally:
        db.close()


async def _execute_tool(name: str, args: dict) -> str:
    if name == "search_memories":
        return await _exec_search_memories(args)
    if name == "create_memory":
        return await _exec_create_memory(args)
    if name == "get_current_time":
        return _exec_get_current_time(args)
    if name == "list_recent_conversations":
        return _exec_list_recent_conversations(args)
    return f"Unknown tool: {name}"


async def run_agent(user_message: str, history: list[dict] | None = None, max_turns: int = 5) -> dict:
    """Agentic loop: calls Ollama with tools until a final text response is produced."""
    messages = list(history or [])
    messages.append({"role": "user", "content": user_message})
    tool_calls_made: list[dict] = []

    for _ in range(max_turns):
        response = await get_ollama().chat.completions.create(
            model=chat_model(),
            messages=messages,
            tools=TOOLS,
            tool_choice="auto",
        )
        choice = response.choices[0]

        if choice.finish_reason == "tool_calls":
            tool_calls = choice.message.tool_calls or []
            messages.append(
                {
                    "role": "assistant",
                    "content": choice.message.content or "",
                    "tool_calls": [
                        {
                            "id": tc.id,
                            "type": "function",
                            "function": {"name": tc.function.name, "arguments": tc.function.arguments},
                        }
                        for tc in tool_calls
                    ],
                }
            )
            for tc in tool_calls:
                args = json.loads(tc.function.arguments or "{}")
                result = await _execute_tool(tc.function.name, args)
                tool_calls_made.append({"tool": tc.function.name, "args": args, "result": result})
                messages.append({"role": "tool", "tool_call_id": tc.id, "content": result})
        else:
            return {"reply": choice.message.content or "", "tool_calls": tool_calls_made}

    return {"reply": "Agent reached maximum turns without a final answer.", "tool_calls": tool_calls_made}
