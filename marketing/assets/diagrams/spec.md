# Diagram Assets Specification

Specifications and Mermaid source for Clavity architecture and workflow diagrams.

## 1. Lifecycle Stages Diagram

```mermaid
flowchart LR
    A["1. Brainstorm (Claude)"] --> B["2. Spec Review (agy panel)"]
    B --> C["3. Plan Review (agy panel)"]
    C --> D["4. Build (Claude)"]
    D --> E["5. Capstone (agy peer)"]
    E --> F["6. Test Audit (agy peer)"]
    F --> G["Task Complete"]
```

## 2. Process Architecture Diagram

```mermaid
flowchart TD
    subgraph Host["Local Workstation Workspace"]
        subgraph Driver["Driver Process"]
            CC["Claude Code CLI"]
            SP["superpowers Plugin"]
            CC --- SP
        end

        subgraph Bridge["Clavity Bridge (MCP)"]
            LS["clavity-ls (Language Server)"]
            MCP["MCP Server Protocol (stdio)"]
            LS --- MCP
        end

        subgraph Peer["Peer Process"]
            AGY["Google Antigravity (agy)"]
            GEMINI["Gemini 3.1 Pro Model"]
            AGY --- GEMINI
        end

        CC <-->|"stdio / MCP"| LS
        LS <-->|"Process Control & IPC"| AGY
    end
```

## 3. Production Render Specs

- **Export Formats:** Vector SVG and high-resolution PNG (2x retina).
- **Background:** Transparent or `#020713`.
- **Node Styling:** Driver elements colored `#ff4b18`; Peer elements colored `#00cfff`.
