# TORQUE Integration Guide - StateTrace

TORQUE (Task Orchestration & Resource Queue Engine) enables parallel task execution for your PowerShell state tracking application.

## Project Overview

StateTrace is a PowerShell-based application with modular architecture, data management, logging, and screenshot capabilities. It includes AI integration via CLAUDE.md.

## MCP Configuration

Add to your `.mcp.json`:

```json
{
  "mcpServers": {
    "torque": {
      "command": "node",
      "args": ["/mnt/c/Users/Werem/Projects/Torque/dist/index.js"],
      "env": {}
    }
  }
}
```

## Recommended Task Templates

### Run Main Application
```
Submit task: "Execute Main/*.ps1 scripts for state tracking"
```

### Module Testing
```
Submit task: "Test all modules in Modules/ directory individually"
```

### Data Processing
```
Submit task: "Process data files in Data/ and generate reports"
```

## Example Workflows

### Full Application Pipeline
```
Create pipeline:
1. Validate all Modules/ syntax
2. Run module unit tests
3. Execute Main/ application
4. Capture state to Data/
5. Generate logs to Logs/
6. Take screenshots to Screenshots/
```

### Parallel Module Testing
```
Queue tasks in parallel:
- "Test Modules/Module1.psm1"
- "Test Modules/Module2.psm1"
- "Test Modules/Module3.psm1"
```

### Data Analysis
```
Submit task: "Analyze Data/ contents and generate summary report"
```

### Log Analysis
```
Submit task: "Parse Logs/ for errors and warnings, create issue report"
```

## Integration with Existing AI Docs

Your project has both AGENTS.md and CLAUDE.md. TORQUE complements these:
- Use TORQUE tasks to validate code before AI handoffs
- Automate context gathering for AI sessions
- Run verification tasks suggested in CLAUDE.md

```
Submit task: "Prepare AI context summary from recent Data/ and Logs/ changes"
```

## Tips

- Use `timeout_minutes: 10` for full application runs
- Tag tasks by module: `tags: ["module-core", "test"]`
- Use pipelines for validate -> run -> capture sequences
- Keep Templates/ updated for consistent output
- Monitor Resources/ for dependency management
