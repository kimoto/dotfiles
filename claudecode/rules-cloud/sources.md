# Sources and connectors

**Several sources: cwd is outside every repo.** No repo's `.claude/` loads — no
allow-list, hooks or skills. Every `CLAUDE.md` still does. Run the repo's checks
by hand; its pre-commit hook did not run. One source loads everything.

**An MCP server name can become a UUID on reconnect**, so `mcp__<name>__…` allow
rules stop matching. Approve once; don't add the UUID.

⚠️ A routine's permissions come from its trigger's `allowed_tools`, not
`settings.json`.
