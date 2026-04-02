---
name: No confirmation for build/run
description: User wants build and run commands executed directly without confirmation prompts
type: feedback
---

Never ask for confirmation when running build_mac.sh or test_design_mac. Execute them directly.

**Why:** User got frustrated by repeated safety confirmation dialogs for shell commands with operators like &&.

**How to apply:** Use separate Bash calls instead of chaining with && to avoid triggering safety prompts. Or run them as single commands without operators.
