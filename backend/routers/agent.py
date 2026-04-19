from fastapi import APIRouter
from pydantic import BaseModel

from utils.llm.tool_agent import run_agent

router = APIRouter(prefix="/v1/agent", tags=["agent"])


class AgentRequest(BaseModel):
    message: str


class ToolCallRecord(BaseModel):
    tool: str
    args: dict
    result: str


class AgentResponse(BaseModel):
    reply: str
    tool_calls: list[ToolCallRecord]


@router.post("/run", response_model=AgentResponse)
async def agent_run(body: AgentRequest):
    result = await run_agent(body.message)
    return AgentResponse(reply=result["reply"], tool_calls=[ToolCallRecord(**tc) for tc in result["tool_calls"]])
