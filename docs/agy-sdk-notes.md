# google-antigravity SDK Surface Notes

Provenance: live inspection of google-antigravity==0.1.3, 2026-06-17.

---

## 1. Import name and version

```python
# The distribution name is 'google-antigravity' but the import path uses
# the namespace package pattern:
from google.antigravity import Agent, LocalAgentConfig
# NOT: import google_antigravity  (ModuleNotFoundError)
```

Version confirmed via `importlib.metadata.version('google-antigravity')` == `0.1.3`.
The package does NOT expose a `__version__` attribute on the top-level module.

---

## 2. Top-level public names

```
['Agent', 'AgentConfig', 'CapabilitiesConfig', 'GeminiConfig', 'GenerationConfig',
 'LocalAgentConfig', 'ModelConfig', 'ModelEntry', 'ThinkingLevel', 'ToolContext',
 'UsageMetadata', 'agent', 'connections', 'conversation', 'hooks', 'tools',
 'triggers', 'types']
```

The concrete headless entry point is **`Agent` + `LocalAgentConfig`**.
`AgentConfig` is an abstract base class (ABC) — do not instantiate it directly.

---

## 3. Headless one-shot entry point

### 3a. Agent constructor

```python
Agent(config: google.antigravity.connections.connection.AgentConfig)
```

`Agent` is an **async context manager** — it must be entered with `async with`.
Calling `agent.chat(...)` outside `async with` raises `RuntimeError`.

### 3b. LocalAgentConfig constructor (concrete config for the local harness)

```python
LocalAgentConfig(
    *,
    # Working directory / file sandbox:
    workspaces: list[str] | None = None,          # default: [os.getcwd()]

    # Auth shorthand (see §4):
    api_key: str | None = None,

    # Model shorthand:
    model: str | None = None,                     # default: "gemini-3.5-flash"

    # Optional extras:
    system_instructions: str | CustomSystemInstructions
                        | TemplatedSystemInstructions | None = None,
    capabilities: CapabilitiesConfig | None = None,
    tools: list[Callable] | None = None,
    policies: list[Any] | None = None,
    hooks: list[Any] | None = None,
    triggers: list[Any] | None = None,
    mcp_servers: list[McpStdioServer | McpStreamableHttpServer] | None = None,
    conversation_id: str | None = None,
    save_dir: str | None = None,
    app_data_dir: str | None = None,
    response_schema: dict | type[BaseModel] | str | None = None,
    skills_paths: list[str] | None = None,
    gemini_config: GeminiConfig | None = None,
    vertex: bool | None = None,
    project: str | None = None,
    location: str | None = None,
)
```

**Working directory / scope:** set via `workspaces=[str(cwd_path)]`.
There is NO `working_directory` parameter. `workspaces` restricts the file tools
to those directories. Default is `[os.getcwd()]` if omitted.

### 3c. Agent.chat signature

```python
async def chat(
    self,
    prompt: str | Image | Document | Audio | Video | SlashCommand
           | Sequence[str | Image | Document | Audio | Video | SlashCommand]
) -> ChatResponse
```

`chat` is a **coroutine** (must be awaited).

### 3d. ChatResponse — return type of Agent.chat

```python
class ChatResponse:
    # Public methods:
    async def text(self) -> str          # drain stream, return full text (coroutine)
    async def resolve(self) -> list[StreamChunk | ToolCall | ToolResult]
    # Properties / iterables:
    chunks          # async cursor over text deltas
    thoughts        # async cursor over thinking chunks
    tool_calls      # async cursor over tool call events
    usage_metadata  # UsageMetadata
    cancel          # cancel method
    structured_output
```

To extract the final response text, await `response.text()`:

```python
text: str = await response.text()
```

`ChatResponse` is an **async lazy-buffered stream**. Multiple independent cursors
are safe to consume sequentially or concurrently.

---

## 4. Non-interactive auth mechanism

**Confirmed env var:** `GEMINI_API_KEY`

Source: `local_connection.py` line 1687-1695:
```python
api_key = (
    self._gemini_config.api_key if self._gemini_config else None
) or os.environ.get("GEMINI_API_KEY")
if not use_vertex and not api_key:
    raise AntigravityValidationError(
        "A Gemini API key is required. Set it via"
        " GeminiConfig(api_key=...) or the GEMINI_API_KEY environment variable."
    )
```

**Two supported non-interactive auth paths:**
1. `GEMINI_API_KEY` env var (checked by `os.environ.get`)
2. `api_key=` constructor param on `LocalAgentConfig` (flows into `GeminiConfig.api_key`)

`GOOGLE_API_KEY` is NOT referenced in the SDK source — `GEMINI_API_KEY` is the only
env var.

**Vertex AI alternative:** `vertex=True` + `project=...` + `location=...` (or
an api_key in Express Mode).

---

## 5. Minimal verified-as-importable snippet

The following object construction does NOT trigger auth or network — it only
validates Pydantic fields:

```python
from google.antigravity import Agent, LocalAgentConfig

config = LocalAgentConfig(
    workspaces=["/path/to/project"],  # sets the working directory scope
    api_key="...",                    # or rely on GEMINI_API_KEY env var
)
# Agent(config) construction is safe (no network, no auth check yet)
agent = Agent(config)
```

The auth check fires inside `async with agent:` (calls `_validate_connection()`
before spawning the harness binary). A minimal headless one-shot:

```python
# UNVERIFIED — not executed (would auth/network/spawn Go binary)
import asyncio
from google.antigravity import Agent, LocalAgentConfig

async def run_once(cwd: str, task: str) -> str:
    config = LocalAgentConfig(
        workspaces=[cwd],
        api_key="YOUR_GEMINI_API_KEY",  # or set GEMINI_API_KEY env var
        policies=[],                     # empty = read-only policy (no writes without confirm)
    )
    async with Agent(config) as agent:
        response = await agent.chat(task)
        return await response.text()

result = asyncio.run(run_once("/path/to/project", "Summarise the README"))
```

---

## 6. Verdict on the assumed API call

The plan's assumed call was:
```python
from google_antigravity import Agent, AgentConfig        # WRONG
Agent(AgentConfig(working_directory=cwd)).chat(task)     # WRONG
```

**All three assumptions are wrong:**

| Assumption | Reality |
|---|---|
| `import google_antigravity` | `from google.antigravity import Agent, LocalAgentConfig` |
| `AgentConfig(working_directory=cwd)` | `LocalAgentConfig(workspaces=[cwd])` — `AgentConfig` is abstract; working dir is `workspaces`, not `working_directory` |
| `.chat(task)` (synchronous) | `async with Agent(config) as agent: await agent.chat(task)` — both Agent and chat are async |
| Result is plain string | `ChatResponse` object; extract with `await response.text()` |

---

## 7. Key files in the installed package

- `google/antigravity/__init__.py` — re-exports
- `google/antigravity/agent.py` — `Agent` class (async CM + `chat`)
- `google/antigravity/types.py` — `ChatResponse`, `LocalAgentConfig`, `GeminiConfig`, etc.
- `google/antigravity/connections/local/local_connection_config.py` — `LocalAgentConfig` source
- `google/antigravity/connections/local/local_connection.py` — harness launch + `_validate_connection` + `GEMINI_API_KEY` lookup
