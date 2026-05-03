# Win32 AI Assistant — Design

**Date:** 2026-05-03
**Status:** Approved, ready for implementation plan
**Scope:** Port full macOS / Linux AI Assistant feature set to Windows.

## Goal

Bring `Tools → AI Assistant` on Windows to full parity with macOS (`MAC_AIAssistantPanel`) and Linux (`GTK_AIAssistantPanel`). The panel must:

- Drive an LLM (Ollama localhost:11434 or DeepSeek `api.deepseek.com`) with the same skill prompt used on Mac/Linux.
- Classify each user message into FORM / RUN / ADD_CODE / CODE / CHAT and dispatch to the corresponding Harbour function (`AIBuildForm`, `AIRunProject`, `AIAddCode`, or chat append).
- Upsert form controls by name (move/resize/relabel existing controls, add genuinely new ones).
- Show one-click suggestion chips above the input bar (model-supplied `next` array, with default fallback).
- Inject active-form context and DBF schema into the user message so the LLM doesn't recreate existing controls or hallucinate field names.
- Persist a DeepSeek API key entered via `/key sk-...`.
- Auto-detect Ollama, prompt to install if missing, auto-pull a default model if none installed.

The current Win32 implementation is a dead UI stub: it creates HWNDs but the Send button is unwired, no HTTP client is invoked, and zero `AI*` Harbour helpers exist in `hbbuilder_win.prg`.

## Constraints / decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| HTTP client | `curl.exe` (process spawn) | Ships with Win10 1803+. No build/distribution change. ~30 LoC vs ~150 for WinHTTP. Mirrors Linux helper pattern. |
| Scope | Full Mac parity (all 11 features) | "Always 3 platforms" rule from project memory. Linux just got ported (a92f1b1) — Win must keep pace. |
| JSON parsing | Harbour PRG side, not C | Win32 has no native JSON; PRG already has `hb_jsonDecode`. Cuts ~200 LoC C. Mac kept it in C only because `NSJSONSerialization` was free. |
| Threading | `CreateThread` + `PostMessage` back to panel HWND | Native Win32 idiom. Mirrors Mac's GCD + main-queue marshaling. Linux's `g_spawn_sync + gtk_events_pending` does not translate to Win32. |

## Architecture

```
ShowAIAssistant() [PRG]
    │
    ▼
W32_AIAssistantPanel() [C, registers HbAIPanel window class]
    ├─ Build child controls (model combo, chat output, chips bar, input, send/clear)
    ├─ Populate combo: DeepSeek items + Ollama tags (sync curl probe)
    ├─ Set initial chips (default set based on AIGetActiveFormClass)
    └─ ShowWindow

AIPanelWndProc (UI thread):
    WM_COMMAND from Send button
        ├─ Echo "> <prompt>" to chat
        ├─ If prompt starts with "/key sk-": save key, refresh combo, return
        ├─ Compose user content = prompt + AIDescribeActiveForm()? + AIDescribeDbf()?
        ├─ Build JSON request body, write to %TEMP%\hbb_ai_req.json
        ├─ Start spinner
        └─ CreateThread(ai_worker, ctx)

ai_worker (worker thread, NO hb_vm calls):
    ├─ CreateProcess curl.exe with stdout pipe
    │     curl -s -X POST -H "Content-Type:application/json"
    │          [-H "Authorization: Bearer <key>"]
    │          -d @%TEMP%\hbb_ai_req.json <url>
    ├─ ReadFile stdout until process exits → buffer cReply
    ├─ if !IsWindow(s_hAIWnd): free, return
    └─ PostMessage(s_hAIWnd, WM_AI_REPLY, 0, (LPARAM)strdup(cReply))

AIPanelWndProc (UI thread):
    WM_AI_REPLY:
        ├─ Stop spinner
        ├─ hb_vmPushDynSym("AIDISPATCHREPLY"); push cReply; hb_vmFunction(1)
        └─ free(cReply)

AIDispatchReply( cRaw ) [PRG]:
    ├─ Strip ```json ... ``` fences
    ├─ Balanced-brace recovery to extract first complete JSON object
    ├─ hb_jsonDecode → hSpec
    ├─ Switch on shape:
    │     action == "run"        → AIRunProject()
    │     action == "add_code"   → AIAddCode( hSpec["code"] )
    │     has controls/w/h/title → AIBuildForm( cRaw ); optional AIAddCode( hSpec["code"] )
    │     has text only          → W32_AIAppendChat( hSpec["text"] )
    │     parse failed           → W32_AIAppendChat( cRaw )    # raw fallback
    └─ Extract hSpec["next"] (3-4 strings) → W32_AISetChips( aChips )
       fallback: AIDefaultChips() based on AIGetActiveFormClass()
```

## Files modified

### `source/hbbuilder_win.prg` — Harbour additions

New / rewritten functions (copy verbatim from `hbbuilder_macos.prg` unless marked):

| Function | Source | Notes |
|----------|--------|-------|
| `ShowAIAssistant()` | rewrite | Probe `where curl.exe`. If missing: MsgInfo "Win10 1803+ ships curl; install or upgrade." Else `W32_AIAssistantPanel()`. |
| `AIRunProject()` | macos verbatim | calls `TBRun()` |
| `AIDescribeDbf( cPath )` | macos verbatim | dbStruct → JSON |
| `AIDescribeActiveForm()` | macos verbatim | UI_GetProp on form + children → JSON |
| `AIGetActiveFormClass()` | macos verbatim | "T" + aForms[nActiveForm][1] |
| `AIAddCode( cCode )` | macos verbatim | uses CodeEditor*/SyncDesignerToCode (already on Win) |
| `AI_FindCtrlByName(hForm,cName)` | macos verbatim | static helper |
| `AI_RewriteClassName(cCode,cNew)` | macos verbatim | static helper |
| `AIBuildForm( cJson )` | macos verbatim | hb_jsonDecode + UI_*New + upsert |
| `AIResizeForm(nW,nH)` | macos verbatim | |
| `AIFitForm()` | macos verbatim | |
| `AIDispatchReply( cRaw )` | **new on Win** | replaces Mac's Obj-C parse and Linux's python helper |
| `AIDefaultChips()` | **new on Win** | returns context-appropriate chip list |
| `AIParseOllamaTags( cJson )` | **new on Win** | called from C to extract model names from `/api/tags` reply |

### `source/hbbuilder_win.prg` — C side

Replace stub `HB_FUNC( W32_AIASSISTANTPANEL )` and add new entry points:

| Symbol | Purpose |
|--------|---------|
| `static HWND s_hAIWnd, s_hAIOutput, s_hAIInput, s_hAICombo, s_hAIChipsBar, s_hAISpinner, s_hAIStatus` | Singleton handles |
| `static char * s_aiDeepseekKey` | Loaded from `%USERPROFILE%\.hbbuilder_deepseek_key` or `DEEPSEEK_API_KEY` env |
| `#define WM_AI_REPLY     (WM_USER + 100)` | Worker → UI: full reply ready |
| `#define WM_AI_APPEND    (WM_USER + 101)` | Append text to chat (used from worker for partial errors) |
| `#define WM_AI_SETCHIPS  (WM_USER + 102)` | Replace chip buttons (called via `W32_AISETCHIPS`) |
| `static const char * AI_SYS_PROMPT` | Skill prompt, copied verbatim from `cocoa_editor.mm:3078-3308`, with "Cocoa tab" → "Win32 tab" |
| `static LRESULT CALLBACK AIPanelWndProc(...)` | Class WndProc; handles WM_COMMAND, WM_CTLCOLOREDIT (dark chat bg), WM_CLOSE (hide), WM_AI_*, WM_SIZE (relayout), WM_DESTROY |
| `static void s_aiAppend(const char *)` | EM_SETSEL/EM_REPLACESEL append, scroll to bottom |
| `static void s_aiLoadKey() / s_aiSaveKey(const char*)` | Persistence |
| `static char * s_aiKeyPath()` | Returns `%USERPROFILE%\.hbbuilder_deepseek_key` |
| `static BOOL s_aiIsDeepseek(const char *)` | strnicmp-based |
| `static char * s_aiFetchOllamaTags()` | Spawns `curl -s --connect-timeout 1 http://localhost:11434/api/tags`, returns stdout; calls `AIParseOllamaTags` for model names |
| `static BOOL s_aiOllamaInstalled()` | `where ollama` returns 0 |
| `static BOOL s_aiTryStartOllama()` | ShellExecute `ollama serve` SW_HIDE |
| `static void s_aiPullModel(const char *)` | Background CreateProcess `ollama pull <model>`; pipes stdout to chat via WM_AI_APPEND |
| `static char * s_aiBuildPayload(BOOL useDeep, const char * model, const char * sysPrompt, const char * userMsg, const char * key)` | Builds JSON, writes to `%TEMP%\hbb_ai_req_<tid>.json`, returns path |
| `static DWORD WINAPI ai_send_thread(LPVOID)` | Worker: CreateProcess curl, ReadFile, PostMessage WM_AI_REPLY |
| `HB_FUNC( W32_AIASSISTANTPANEL )` | Register class, build window, populate combo, init chips |
| `HB_FUNC( W32_AIAPPENDCHAT )` | `( cText )` from PRG: append to chat |
| `HB_FUNC( W32_AISETCHIPS )` | `( aChips )` from PRG: clear and rebuild chip buttons |
| `HB_FUNC( W32_AIDEEPSEEKKEY )` | `( cKey )` save / `()` get — used by `/key` flow |

### Layout

Window 420×550 (matches macOS 450×550). Anchored top-right of main window minus 40px margin, vertically centered.

```
┌───────────────────────────────────────────┐
│ Model: [combo ▾]   [spinner] [Clear]      │  Top row, y=8 h=24
├───────────────────────────────────────────┤
│                                           │
│  Chat output (read-only EDIT, dark bg)    │  y=36, fills to chips
│  Consolas 11pt, #1E1E1E bg, #D4D4D4 fg    │
│                                           │
├───────────────────────────────────────────┤
│ [chip] [chip] [chip] [chip]               │  y=h-78 h=30
├───────────────────────────────────────────┤
│ [input field          ]    [Send]         │  y=h-44 h=24
├───────────────────────────────────────────┤
│ Status: Ready | Model: deepseek-v4-flash  │  y=h-18 h=18
└───────────────────────────────────────────┘
```

WM_SIZE recomputes: chat = (panelW-16, panelH - 36 - 78 - 44 - 18), chips/input/status anchored to bottom.

## Worker thread flow

1. Main thread calls `ai_send` (Send button). Builds JSON payload, writes to temp file, allocates `AICtx { wchar* cmdline; HWND hWnd; }`, `CreateThread(ai_send_thread, ctx)`.
2. Worker thread `CreateProcess`'s curl with `STARTUPINFO.hStdOutput` = pipe write end, `dwFlags |= STARTF_USESTDHANDLES`, `CREATE_NO_WINDOW`.
3. `CloseHandle` on pipe write end (otherwise ReadFile blocks forever after curl exits).
4. ReadFile loop into `growable buffer`. Cap at 1 MB; truncate beyond.
5. `WaitForSingleObject` on process handle (timeout 200s).
6. If `IsWindow(ctx->hWnd)`: `PostMessage(WM_AI_REPLY, 0, (LPARAM)buffer)`. Else `free(buffer)`.
7. `free(ctx)`. `CloseHandle` process / thread.

## Dark mode

Panel: `DwmSetWindowAttribute(DWMWA_USE_IMMERSIVE_DARK_MODE, &TRUE)` when `g_bDarkIDE`. Same as Project Inspector pattern at `hbbuilder_win.prg:6516-6519`.

Chat EDIT control: handle `WM_CTLCOLOREDIT` → `SetBkColor(0x1E1E1E)`, `SetTextColor(0xD4D4D4)`, return brush. Match GTK's `#1E1E1E / #D4D4D4`.

## Failure modes

| Condition | Behavior |
|-----------|----------|
| `curl.exe` missing (Win < 10.1803) | `ShowAIAssistant` MsgInfo: "Win10 1803+ required, or install curl manually." Panel does not open. |
| Ollama not running, no DeepSeek key, key install declined | Chat: "Ollama not detected. Type `/key sk-...` to use DeepSeek, or install Ollama from https://ollama.com/download". Combo shows DeepSeek items only. |
| Ollama running, no models | Chat: "Pulling default model gemma3...". `s_aiPullModel("gemma3")` runs in background, stdout streamed to chat. |
| LLM returns invalid JSON | Balanced-brace recovery in `AIDispatchReply`. If still invalid: append raw text as chat. |
| User closes panel mid-call | Worker thread checks `IsWindow` before `PostMessage`; frees buffer otherwise. |
| Worker process timeout (>200s) | TerminateProcess; chat: "[Request timed out]". |
| `AIRunProject` not registered | hb_dynsymFindName returns NULL — wrap with check; chat: "[AIRunProject not registered]". |

## Out of scope

- Streaming responses (Mac/Linux don't stream either; would require separate WM_AI_PARTIAL flow)
- Multi-turn conversation history (panel is stateless single-shot per Send)
- Token counters
- Tool/function calling protocol
- LM Studio backend (Ollama API-compatible, but not auto-detected)

## Testing

Manual only (UI). Procedure:

1. Tools menu → AI Assistant. Panel appears top-right of main window in dark mode.
2. With Ollama running + `codellama` pulled:
   - "haz un login" → form generated, controls placed.
   - "centralos" → buttons reposition (upsert by name, no duplicates).
   - "ajusta tamaño form" → form resizes.
   - "run" → builds and launches project (TBRun).
   - "añade fibonacci" → code appended green-marked to active .prg tab.
3. `/key sk-xxxxxxxx` → key saved to `%USERPROFILE%\.hbbuilder_deepseek_key`. Combo gets DeepSeek items at top. Selecting `deepseek-v4-flash` and re-asking uses DeepSeek API.
4. Close panel mid-`run` request: no crash, no leak.
5. Toggle `g_bDarkIDE`: panel reskins on next open.
6. Without Ollama installed and DeepSeek key not set: install prompt opens browser to ollama.com/download; chat explains.
7. Active form has `btnOk`,`btnCancel`. Ask: "centralos" → both buttons reposition, no dupes. Verify by inspecting `aForms[1][3]` regenerated source.

## Verification before claiming done

- `bcc32` clean compile of `source/hbbuilder_win.prg`
- Smoke test 1, 2, 3, 4 above
- No compiler warnings on the new C functions
