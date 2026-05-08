# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`ccxt_ocx` is an Elixir library — purpose TBD (CCXT-family sibling of `ccxt_extract` and `ccxt_client`).

## Standard imports

@~/.claude/includes/across-instances.md
@~/.claude/includes/critical-rules.md
@~/.claude/includes/task-prioritization.md
@~/.claude/includes/task-writing.md
@~/.claude/includes/workflow-philosophy.md
@~/.claude/includes/web-command.md
@~/.claude/includes/elixir-setup.md
@~/.claude/includes/ex-unit-json.md
@~/.claude/includes/dialyzer-json.md
@~/.claude/includes/code-style.md
@~/.claude/includes/development-commands.md
@~/.claude/includes/development-philosophy.md
@~/.claude/includes/elixir-volt.md
@~/.claude/includes/oxc.md
@~/.claude/includes/quickbeam.md
@~/.claude/includes/reach.md
@~/.claude/includes/cloud-agent-environments.md
@~/.claude/includes/linear-workflow.md
@~/.claude/includes/delegation.md
@~/.claude/includes/delegation-rules.md

---

## Tidewave

This project's Tidewave port is **4014** (registered in `~/.claude/tidewave-ports.md`).

```bash
iex -S mix tidewave   # listens on http://localhost:4014/tidewave/mcp
```

`.mcp.json` is project-scoped. After cloning, restart Claude Code so the MCP server registers.

## Common commands

```bash
mix deps.get
time mix compile --warnings-as-errors
mix test.json
mix dialyzer.json --quiet
mix credo --strict --format json
mix sobelow --mark-skip-all
```

## Why these dependency floors

- `quickbeam ~> 0.10.4`: 0.10.3 fixed an upstream QuickJS-NG closure GC bug that
  affected handlers captured in long-lived runtimes — exactly the WS-streaming
  pattern in Phase 3 and authenticated WS streams in Task T5. Do not lower.
