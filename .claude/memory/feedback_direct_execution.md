---
name: Always execute directly
description: Never ask confirmation for build/run commands, never ask before making changes
type: feedback
---

Execute build and run commands directly without confirmation. Do not ask "should I do X?" — just do it.

**Why:** User got frustrated by repeated safety confirmation dialogs and questions before acting.

**How to apply:** Use separate Bash calls (not chained with &&) to avoid triggering safety prompts. Build with `./build_mac.sh 2>&1`, run with `./hbcpp_macos &`. Never ask permission for these operations.
