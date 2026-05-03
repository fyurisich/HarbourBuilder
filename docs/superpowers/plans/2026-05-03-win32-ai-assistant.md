# Win32 AI Assistant Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace dead Win32 AI Assistant stub with full Mac/Linux feature parity — skill-driven FORM/RUN/ADD_CODE dispatch, control upsert, chips, /key persistence, Ollama/DeepSeek backends.

**Architecture:** Native Win32 panel registered as `HbAIPanel` class. HTTP via `curl.exe` spawned in worker thread; `PostMessage(WM_AI_REPLY)` marshals reply back to UI thread. JSON parsed on PRG side via `hb_jsonDecode`, dispatched to `AIBuildForm` / `AIRunProject` / `AIAddCode` (ports of macOS impl). Skill system prompt copied verbatim from `cocoa_editor.mm` with palette-tab name swapped.

**Tech Stack:** Harbour, BCC32 (C89-strict), Win32 API, curl.exe (Win10 1803+), Ollama / DeepSeek HTTP APIs.

**Reference design:** `docs/superpowers/specs/2026-05-03-win32-ai-assistant-design.md`

**Build command (run from `source/`):** `build_now.bat`. Output `bin/hbbuilder_win.exe`. Build must be clean before commit; warnings about decl-after-statement are fatal under bcc32.

**Testing:** No automated test suite for HbBuilder UI. Verification = `build_now.bat` clean + manual smoke checklist per task. Each task ends with a build+commit.

---

## Reference snippets used by multiple tasks

The C-side stub being replaced lives at `source/hbbuilder_win.prg:6554-6646` (it is a heredoc-style C function inside the .prg via Harbour's inline C feature; the .prg file mixes Harbour and C sections — search for `#pragma BEGINDUMP` blocks).

The macOS reference impl is at:
- C/Obj-C: `source/backends/cocoa/cocoa_editor.mm:2664-3694`
- PRG: `source/hbbuilder_macos.prg:4894-5278`

The Linux GTK reference impl (closest to the architecture we want, since it also dispatches via HB_FUNC calls into PRG) is at:
- C: `source/backends/gtk3/gtk3_core.c:9138-9879`
- PRG: `source/hbbuilder_linux.prg:3498-3950`

When a task says "copy verbatim from `hbbuilder_macos.prg:NNNN-MMMM`," it means: open that range, paste exactly into the corresponding location in `hbbuilder_win.prg`, with no semantic edits. The macOS Harbour helpers do not reference any Cocoa-specific globals.

---

## Task 1: C — register `HbAIPanel` window class with minimal WndProc

**Files:**
- Modify: `source/hbbuilder_win.prg:6554-6646` (replace the stub `W32_AIASSISTANTPANEL` body)

**Goal:** Replace the dead-class stub with a real registered class. After this task the panel still won't do anything functional, but it opens, can be closed, registers properly, and respects dark mode.

- [ ] **Step 1: Locate the existing inline C section**

The Win32 .prg embeds C in `#pragma BEGINDUMP / #pragma ENDDUMP` blocks. Find the one that contains `HB_FUNC( W32_AIASSISTANTPANEL )` (line 6555). Above it (within the same `BEGINDUMP` block) you will add the new globals, WM constants, and `AIPanelWndProc`.

- [ ] **Step 2: Add WM_AI message constants and forward decls near the top of the C dump block (just below the existing `#include` lines or near other `#define WM_...`)**

```c
#define WM_AI_REPLY     (WM_USER + 100)   /* worker -> UI: full reply ready,  lParam = char* heap buffer */
#define WM_AI_APPEND    (WM_USER + 101)   /* worker -> UI: append text,       lParam = char* heap buffer */
#define WM_AI_SETCHIPS  (WM_USER + 102)   /* PRG    -> UI: replace chips,     lParam = HGLOBAL of strings */

static HWND  s_hAIWnd       = NULL;
static HWND  s_hAIOutput    = NULL;
static HWND  s_hAIInput     = NULL;
static HWND  s_hAICombo     = NULL;
static HWND  s_hAIChipsBar  = NULL;
static HWND  s_hAISend      = NULL;
static HWND  s_hAIClear     = NULL;
static HWND  s_hAIStatus    = NULL;
static HFONT s_hAIChatFont  = NULL;
static HFONT s_hAIUiFont    = NULL;
static HBRUSH s_hAIChatBrush = NULL;
static char * s_aiDeepseekKey = NULL;

static LRESULT CALLBACK AIPanelWndProc( HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam );
```

- [ ] **Step 3: Add the minimal `AIPanelWndProc` body**

Place after the globals, before `HB_FUNC( W32_AIASSISTANTPANEL )`:

```c
static LRESULT CALLBACK AIPanelWndProc( HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam )
{
   switch( msg )
   {
   case WM_CTLCOLOREDIT:
   case WM_CTLCOLORSTATIC:
      if( (HWND)lParam == s_hAIOutput ) {
         HDC hdc = (HDC)wParam;
         SetBkColor( hdc, RGB(0x1E,0x1E,0x1E) );
         SetTextColor( hdc, RGB(0xD4,0xD4,0xD4) );
         if( !s_hAIChatBrush )
            s_hAIChatBrush = CreateSolidBrush( RGB(0x1E,0x1E,0x1E) );
         return (LRESULT) s_hAIChatBrush;
      }
      break;
   case WM_CLOSE:
      ShowWindow( hWnd, SW_HIDE );
      return 0;
   case WM_DESTROY:
      s_hAIWnd = NULL;
      return 0;
   }
   return DefWindowProc( hWnd, msg, wParam, lParam );
}
```

- [ ] **Step 4: Replace the body of `HB_FUNC( W32_AIASSISTANTPANEL )` with a class-registered window builder**

Replace lines 6554-6646 (the entire stub) with:

```c
/* W32_AIAssistantPanel() - AI coding assistant (Ollama + DeepSeek) */
HB_FUNC( W32_AIASSISTANTPANEL )
{
   static BOOL bReg = FALSE;
   WNDCLASSA wc = {0};
   HWND hOwner;
   RECT rc;
   LOGFONTA lf = {0};
   int panW = 420, panH = 560;

   if( s_hAIWnd && IsWindow(s_hAIWnd) ) {
      ShowWindow( s_hAIWnd, SW_SHOW );
      SetForegroundWindow( s_hAIWnd );
      return;
   }

   if( !bReg ) {
      wc.lpfnWndProc   = AIPanelWndProc;
      wc.hInstance     = GetModuleHandle(NULL);
      wc.hCursor       = LoadCursor(NULL, IDC_ARROW);
      wc.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
      wc.lpszClassName = "HbAIPanel";
      RegisterClassA( &wc );
      bReg = TRUE;
   }

   hOwner = GetActiveWindow();
   GetWindowRect( hOwner, &rc );

   s_hAIWnd = CreateWindowExA( WS_EX_TOOLWINDOW,
      "HbAIPanel", "AI Assistant",
      WS_POPUP|WS_CAPTION|WS_SYSMENU|WS_THICKFRAME|WS_VISIBLE,
      rc.right - panW - 16, rc.top + 60, panW, panH,
      NULL, NULL, GetModuleHandle(NULL), NULL );

   if( g_bDarkIDE ) {
      BOOL bDark = TRUE;
      DwmSetWindowAttribute( s_hAIWnd, DWMWA_USE_IMMERSIVE_DARK_MODE,
                             &bDark, sizeof(bDark) );
   }

   s_hAIUiFont = (HFONT) GetStockObject( DEFAULT_GUI_FONT );
   lf.lfHeight = -14;
   lf.lfCharSet = DEFAULT_CHARSET;
   lf.lfPitchAndFamily = FIXED_PITCH;
   lstrcpyA( lf.lfFaceName, "Consolas" );
   s_hAIChatFont = CreateFontIndirectA( &lf );

   /* Children created in later tasks. For now leave as bare panel. */
}
```

- [ ] **Step 5: Build**

```
cd source
build_now.bat
```

Expected: `LINK OK`. If decl-after-statement errors appear, move every declaration to top of its block.

- [ ] **Step 6: Smoke**

Run `bin\hbbuilder_win.exe`. Tools menu → AI Assistant. Empty 420x560 panel appears top-right of main window. Close it via X — no crash. Reopen — same panel.

- [ ] **Step 7: Commit**

```
git add source/hbbuilder_win.prg
git commit -m "feat(win-ai): register HbAIPanel class, replace dead STATIC stub

Empty registered panel with WndProc, dark-mode-aware via DwmSetWindowAttribute,
WM_CTLCOLOREDIT hook ready for chat dark theme. No functional UI yet."
```

---

## Task 2: C — embed AI_SYS_PROMPT skill string

**Files:**
- Modify: `source/hbbuilder_win.prg` (inline C dump block)
- Read-only reference: `source/backends/cocoa/cocoa_editor.mm:3078-3308`

**Goal:** Add the verbatim skill prompt as a C string constant `AI_SYS_PROMPT`. This is the longest single piece of the port.

- [ ] **Step 1: Open `source/backends/cocoa/cocoa_editor.mm` lines 3078-3308**

The Mac code uses Objective-C `@"..."` literals concatenated with whitespace. Our C version uses standard `"..."` literals (drop the `@`).

- [ ] **Step 2: Add `static const char * AI_SYS_PROMPT = ...` near the top of the C dump block, after the global declarations from Task 1**

Strategy: copy the entire literal between `NSString * sysPrompt =` and the trailing semicolon at line 3308 in `cocoa_editor.mm`. Substitute every `@"` with `"` and remove no other escaping (the existing escapes — `\"`, `\\\"`, `\n` — are already C-compatible).

Two semantic adjustments:
1. Replace `"          • Cocoa tab: TTabControl, TTreeView, TListView, TProgressBar.\n"` with `"          • Win32 tab: TTabControl, TTreeView, TListView, TProgressBar.\n"`
2. Replace `"        If the user asks to LIST/SHOW the palette controls, respond as CHAT (plain text) "` line — leave as-is. The catalog list above already names the right tab.

- [ ] **Step 3: Sanity-check the constant compiles**

```
cd source
build_now.bat
```

Expected: `C OK`. A common failure mode is unterminated string literal — bcc32 reports the line. Fix by joining adjacent string literals correctly (no comma, just whitespace).

- [ ] **Step 4: Commit**

```
git add source/hbbuilder_win.prg
git commit -m "feat(win-ai): embed AI_SYS_PROMPT skill string

Verbatim port of cocoa_editor.mm:3078-3308 with Cocoa->Win32 palette tab
naming. Same FORM/RUN/ADD_CODE/CODE/CHAT routing rules across all 3 platforms."
```

---

## Task 3: C — build full panel UI in `W32_AIAssistantPanel`

**Files:**
- Modify: `source/hbbuilder_win.prg` (extend `HB_FUNC( W32_AIASSISTANTPANEL )` from Task 1)

**Goal:** Add chat output, model combo, chips bar, input field, send/clear buttons, status label. No event wiring yet.

- [ ] **Step 1: Append child-control creation to `W32_AIASSISTANTPANEL`, just before the closing brace**

```c
   /* Layout constants */
   {
      int topRowH = 28;
      int chipsH  = 30;
      int inputH  = 26;
      int statusH = 18;
      int margin  = 6;
      int chatY   = margin + topRowH + 4;
      int chatH   = panH - chatY - chipsH - inputH - statusH - 4*margin;

      /* Top row: Model label + combo + Clear */
      CreateWindowExA( 0, "STATIC", "Model:", WS_CHILD|WS_VISIBLE,
         margin, margin + 6, 42, 18, s_hAIWnd, NULL, GetModuleHandle(NULL), NULL );
      s_hAICombo = CreateWindowExA( 0, "COMBOBOX", NULL,
         WS_CHILD|WS_VISIBLE|CBS_DROPDOWNLIST|WS_VSCROLL,
         margin + 50, margin, panW - 80 - margin*2, 240,
         s_hAIWnd, (HMENU)2010, GetModuleHandle(NULL), NULL );
      SendMessage( s_hAICombo, WM_SETFONT, (WPARAM) s_hAIUiFont, TRUE );
      s_hAIClear = CreateWindowExA( 0, "BUTTON", "Clear",
         WS_CHILD|WS_VISIBLE|BS_PUSHBUTTON,
         panW - margin - 70, margin, 70, topRowH,
         s_hAIWnd, (HMENU)2011, GetModuleHandle(NULL), NULL );
      SendMessage( s_hAIClear, WM_SETFONT, (WPARAM) s_hAIUiFont, TRUE );

      /* Chat output (read-only EDIT, dark bg via WM_CTLCOLOREDIT) */
      s_hAIOutput = CreateWindowExA( WS_EX_CLIENTEDGE, "EDIT",
         "AI Assistant ready.\r\n",
         WS_CHILD|WS_VISIBLE|WS_VSCROLL|ES_MULTILINE|ES_READONLY|ES_AUTOVSCROLL,
         margin, chatY, panW - margin*2, chatH,
         s_hAIWnd, NULL, GetModuleHandle(NULL), NULL );
      SendMessage( s_hAIOutput, WM_SETFONT, (WPARAM) s_hAIChatFont, TRUE );

      /* Chips bar (child window holding chip buttons; we reposition via WM_SIZE in later task) */
      s_hAIChipsBar = CreateWindowExA( 0, "STATIC", NULL, WS_CHILD|WS_VISIBLE,
         margin, chatY + chatH + margin, panW - margin*2, chipsH,
         s_hAIWnd, (HMENU)2020, GetModuleHandle(NULL), NULL );

      /* Input field */
      s_hAIInput = CreateWindowExA( WS_EX_CLIENTEDGE, "EDIT", "",
         WS_CHILD|WS_VISIBLE|ES_AUTOHSCROLL,
         margin, chatY + chatH + chipsH + margin*2,
         panW - margin*2 - 76, inputH,
         s_hAIWnd, (HMENU)2030, GetModuleHandle(NULL), NULL );
      SendMessage( s_hAIInput, WM_SETFONT, (WPARAM) s_hAIUiFont, TRUE );

      /* Send button */
      s_hAISend = CreateWindowExA( 0, "BUTTON", "Send",
         WS_CHILD|WS_VISIBLE|BS_DEFPUSHBUTTON,
         panW - margin - 70, chatY + chatH + chipsH + margin*2, 70, inputH,
         s_hAIWnd, (HMENU)2031, GetModuleHandle(NULL), NULL );
      SendMessage( s_hAISend, WM_SETFONT, (WPARAM) s_hAIUiFont, TRUE );

      /* Status bar */
      s_hAIStatus = CreateWindowExA( 0, "STATIC", "Status: Ready",
         WS_CHILD|WS_VISIBLE|SS_LEFT,
         margin, panH - statusH - margin, panW - margin*2, statusH,
         s_hAIWnd, NULL, GetModuleHandle(NULL), NULL );
      SendMessage( s_hAIStatus, WM_SETFONT, (WPARAM) s_hAIUiFont, TRUE );

      /* Default model list (dynamic ollama tags added in later task) */
      SendMessageA( s_hAICombo, CB_ADDSTRING, 0, (LPARAM)"deepseek-v4-flash" );
      SendMessageA( s_hAICombo, CB_ADDSTRING, 0, (LPARAM)"deepseek-chat" );
      SendMessageA( s_hAICombo, CB_ADDSTRING, 0, (LPARAM)"codellama" );
      SendMessageA( s_hAICombo, CB_ADDSTRING, 0, (LPARAM)"llama3" );
      SendMessageA( s_hAICombo, CB_ADDSTRING, 0, (LPARAM)"deepseek-coder" );
      SendMessageA( s_hAICombo, CB_ADDSTRING, 0, (LPARAM)"gemma3" );
      SendMessage( s_hAICombo, CB_SETCURSEL, 0, 0 );
   }
```

- [ ] **Step 2: Build**

```
cd source
build_now.bat
```

Expected: `LINK OK`.

- [ ] **Step 3: Smoke**

Tools → AI Assistant. Verify: chat region dark gray (#1E1E1E) with "AI Assistant ready." text in light gray, model combo populated with 6 entries, input field + Send + Clear visible, status bar at bottom.

Note: Send button does nothing yet. That is wired in Task 6/7.

- [ ] **Step 4: Commit**

```
git add source/hbbuilder_win.prg
git commit -m "feat(win-ai): full panel layout with chat/combo/chips/input/status

All child controls created. Chat dark bg via WM_CTLCOLOREDIT. Send/Clear
buttons unwired (next task). Model combo seeded with deepseek + ollama defaults."
```

---

## Task 4: C — chat append helper + `W32_AIAppendChat` HB_FUNC

**Files:**
- Modify: `source/hbbuilder_win.prg` (inline C dump block)

**Goal:** Provide `s_aiAppend(const char *)` callable from C and `W32_AIAppendChat(cText)` callable from PRG.

- [ ] **Step 1: Add `s_aiAppend` helper above `AIPanelWndProc`**

```c
static void s_aiAppend( const char * txt )
{
   int n;
   if( !s_hAIOutput || !txt || !*txt ) return;
   n = (int) SendMessageA( s_hAIOutput, WM_GETTEXTLENGTH, 0, 0 );
   SendMessageA( s_hAIOutput, EM_SETSEL, n, n );
   SendMessageA( s_hAIOutput, EM_REPLACESEL, FALSE, (LPARAM)txt );
   SendMessageA( s_hAIOutput, EM_SCROLLCARET, 0, 0 );
}
```

- [ ] **Step 2: Add `WM_AI_APPEND` handler in `AIPanelWndProc`**

Insert a case before `WM_CLOSE`:

```c
   case WM_AI_APPEND:
      if( lParam ) {
         char * p = (char *) lParam;
         s_aiAppend( p );
         free( p );
      }
      return 0;
```

- [ ] **Step 3: Add `HB_FUNC( W32_AIAPPENDCHAT )` near the other AI HB_FUNCs**

```c
HB_FUNC( W32_AIAPPENDCHAT )
{
   const char * t = hb_parc(1);
   if( t && s_hAIWnd ) {
      /* Convert LF to CRLF for EDIT control */
      int len = (int) strlen( t );
      char * buf = (char *) malloc( (size_t)len * 2 + 1 );
      char * p = buf;
      int i;
      for( i = 0; i < len; i++ ) {
         if( t[i] == '\n' && (i == 0 || t[i-1] != '\r') ) *p++ = '\r';
         *p++ = t[i];
      }
      *p = 0;
      s_aiAppend( buf );
      free( buf );
   }
}
```

- [ ] **Step 4: Build + commit**

```
cd source
build_now.bat
git add source/hbbuilder_win.prg
git commit -m "feat(win-ai): s_aiAppend + W32_AIAppendChat for chat output

EDIT control append via EM_SETSEL/EM_REPLACESEL with LF->CRLF normalization.
Callable from PRG via W32_AIAppendChat for dispatch results."
```

---

## Task 5: C — DeepSeek key persistence + `/key` plumbing

**Files:**
- Modify: `source/hbbuilder_win.prg` (inline C dump block)

**Goal:** Load/save key at `%USERPROFILE%\.hbbuilder_deepseek_key`. Expose to PRG.

- [ ] **Step 1: Add helpers above `AIPanelWndProc`**

```c
static void s_aiKeyPath( char * out, int max )
{
   char prof[MAX_PATH] = "";
   DWORD n = GetEnvironmentVariableA( "USERPROFILE", prof, MAX_PATH );
   if( n == 0 ) lstrcpynA( prof, ".", MAX_PATH );
   _snprintf( out, max, "%s\\.hbbuilder_deepseek_key", prof );
   out[max-1] = 0;
}

static void s_aiLoadKey( void )
{
   char path[MAX_PATH], buf[256];
   const char * env;
   HANDLE h;
   DWORD got = 0;
   int i;
   if( s_aiDeepseekKey ) return;
   env = getenv("DEEPSEEK_API_KEY");
   if( env && *env ) { s_aiDeepseekKey = _strdup(env); return; }
   s_aiKeyPath( path, MAX_PATH );
   h = CreateFileA( path, GENERIC_READ, FILE_SHARE_READ, NULL,
                    OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL );
   if( h == INVALID_HANDLE_VALUE ) return;
   if( ReadFile( h, buf, sizeof(buf)-1, &got, NULL ) && got > 0 ) {
      buf[got] = 0;
      for( i = (int)got - 1; i >= 0 && (buf[i]=='\n'||buf[i]=='\r'||buf[i]==' '); i-- )
         buf[i] = 0;
      if( buf[0] ) s_aiDeepseekKey = _strdup(buf);
   }
   CloseHandle(h);
}

static void s_aiSaveKey( const char * key )
{
   char path[MAX_PATH];
   HANDLE h;
   DWORD wr = 0;
   if( !key || !*key ) return;
   if( s_aiDeepseekKey ) { free( s_aiDeepseekKey ); s_aiDeepseekKey = NULL; }
   s_aiDeepseekKey = _strdup( key );
   s_aiKeyPath( path, MAX_PATH );
   h = CreateFileA( path, GENERIC_WRITE, 0, NULL,
                    CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL );
   if( h != INVALID_HANDLE_VALUE ) {
      WriteFile( h, key, (DWORD)strlen(key), &wr, NULL );
      CloseHandle( h );
   }
}

static BOOL s_aiIsDeepseek( const char * model )
{
   return model && _strnicmp( model, "deepseek", 8 ) == 0;
}
```

- [ ] **Step 2: Add HB_FUNC**

```c
HB_FUNC( W32_AIDEEPSEEKKEY )
{
   if( HB_ISCHAR(1) ) {
      s_aiSaveKey( hb_parc(1) );
      hb_retc( s_aiDeepseekKey ? s_aiDeepseekKey : "" );
   } else {
      if( !s_aiDeepseekKey ) s_aiLoadKey();
      hb_retc( s_aiDeepseekKey ? s_aiDeepseekKey : "" );
   }
}
```

- [ ] **Step 3: Call `s_aiLoadKey()` at the top of `HB_FUNC( W32_AIASSISTANTPANEL )`, before the `if( s_hAIWnd...)` early-return**

```c
   s_aiLoadKey();
```

- [ ] **Step 4: Build + commit**

```
cd source
build_now.bat
git add source/hbbuilder_win.prg
git commit -m "feat(win-ai): DeepSeek key persistence

Load from DEEPSEEK_API_KEY env or %USERPROFILE%\.hbbuilder_deepseek_key.
W32_AIDeepseekKey(cKey?) PRG accessor (set when arg given, get otherwise)."
```

---

## Task 6: C — payload builder + `ai_send_thread` worker

**Files:**
- Modify: `source/hbbuilder_win.prg` (inline C dump block)

**Goal:** Build the JSON request body to a temp file and run curl.exe in a worker thread, posting WM_AI_REPLY back.

- [ ] **Step 1: Add forward decls and a small JSON-string-escape helper**

```c
typedef struct {
   HWND  hPanel;
   char  cmdline[ 8192 ];
} AICTX;

static DWORD WINAPI ai_send_thread( LPVOID p );

static void s_aiJsonEsc( const char * in, char * out, int max )
{
   int o = 0;
   while( *in && o < max - 8 ) {
      unsigned char c = (unsigned char)*in++;
      switch( c ) {
         case '"':  out[o++] = '\\'; out[o++] = '"';  break;
         case '\\': out[o++] = '\\'; out[o++] = '\\'; break;
         case '\n': out[o++] = '\\'; out[o++] = 'n';  break;
         case '\r': out[o++] = '\\'; out[o++] = 'r';  break;
         case '\t': out[o++] = '\\'; out[o++] = 't';  break;
         default:
            if( c < 0x20 ) {
               o += _snprintf( out + o, max - o, "\\u%04x", c );
            } else {
               out[o++] = (char)c;
            }
      }
   }
   out[o] = 0;
}
```

- [ ] **Step 2: Add `s_aiBuildPayload` — writes JSON request body to `%TEMP%\hbb_ai_req_<pid>.json`, returns full curl command line in `cmdOut`**

```c
static BOOL s_aiBuildPayload( BOOL useDeep, const char * model,
                              const char * userMsg, const char * key,
                              char * cmdOut, int cmdMax,
                              char * pathOut, int pathMax )
{
   char tmpDir[MAX_PATH], path[MAX_PATH], * sysEsc, * userEsc;
   DWORD pid = GetCurrentProcessId();
   FILE * f;
   int sysLen, userLen;

   GetTempPathA( MAX_PATH, tmpDir );
   _snprintf( path, MAX_PATH, "%shbb_ai_req_%lu.json", tmpDir, (unsigned long)pid );
   path[MAX_PATH-1] = 0;
   lstrcpynA( pathOut, path, pathMax );

   sysLen  = (int)( strlen( AI_SYS_PROMPT ) * 2 + 32 );
   userLen = (int)( strlen( userMsg ) * 2 + 32 );
   sysEsc  = (char *) malloc( sysLen );
   userEsc = (char *) malloc( userLen );
   s_aiJsonEsc( AI_SYS_PROMPT, sysEsc,  sysLen );
   s_aiJsonEsc( userMsg,       userEsc, userLen );

   f = fopen( path, "wb" );
   if( !f ) { free(sysEsc); free(userEsc); return FALSE; }
   if( useDeep ) {
      fprintf( f,
         "{\"model\":\"%s\",\"stream\":false,\"temperature\":0.2,"
         "\"messages\":["
            "{\"role\":\"system\",\"content\":\"%s\"},"
            "{\"role\":\"user\",\"content\":\"%s\"}"
         "]}",
         model, sysEsc, userEsc );
   } else {
      fprintf( f,
         "{\"model\":\"%s\",\"stream\":false,"
         "\"options\":{\"temperature\":0.2},"
         "\"messages\":["
            "{\"role\":\"system\",\"content\":\"%s\"},"
            "{\"role\":\"user\",\"content\":\"%s\"}"
         "]}",
         model, sysEsc, userEsc );
   }
   fclose( f );
   free( sysEsc ); free( userEsc );

   if( useDeep ) {
      _snprintf( cmdOut, cmdMax,
         "curl.exe -s -m 200 -X POST "
         "-H \"Content-Type: application/json\" "
         "-H \"Authorization: Bearer %s\" "
         "-d @\"%s\" "
         "https://api.deepseek.com/v1/chat/completions",
         key ? key : "", path );
   } else {
      _snprintf( cmdOut, cmdMax,
         "curl.exe -s -m 200 -X POST "
         "-H \"Content-Type: application/json\" "
         "-d @\"%s\" "
         "http://localhost:11434/api/chat",
         path );
   }
   cmdOut[cmdMax-1] = 0;
   return TRUE;
}
```

- [ ] **Step 3: Add `ai_send_thread` worker — runs curl, captures stdout, posts WM_AI_REPLY**

```c
static DWORD WINAPI ai_send_thread( LPVOID p )
{
   AICTX * ctx = (AICTX *) p;
   HANDLE hRd = NULL, hWr = NULL;
   SECURITY_ATTRIBUTES sa;
   STARTUPINFOA si;
   PROCESS_INFORMATION pi;
   char * buf;
   DWORD bufCap = 65536, bufLen = 0;
   DWORD got;
   char tmp[4096];

   sa.nLength = sizeof(sa);
   sa.bInheritHandle = TRUE;
   sa.lpSecurityDescriptor = NULL;
   if( !CreatePipe( &hRd, &hWr, &sa, 0 ) ) goto fail;
   SetHandleInformation( hRd, HANDLE_FLAG_INHERIT, 0 );

   memset( &si, 0, sizeof(si) );
   si.cb = sizeof(si);
   si.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
   si.hStdOutput = hWr;
   si.hStdError  = hWr;
   si.hStdInput  = GetStdHandle( STD_INPUT_HANDLE );
   si.wShowWindow = SW_HIDE;

   memset( &pi, 0, sizeof(pi) );
   if( !CreateProcessA( NULL, ctx->cmdline, NULL, NULL, TRUE,
                        CREATE_NO_WINDOW, NULL, NULL, &si, &pi ) ) {
      CloseHandle(hRd); CloseHandle(hWr); goto fail;
   }
   CloseHandle( hWr );  /* parent must close write end */

   buf = (char *) malloc( bufCap );
   while( ReadFile( hRd, tmp, sizeof(tmp), &got, NULL ) && got > 0 ) {
      if( bufLen + got + 1 > bufCap ) {
         bufCap = (bufCap + got) * 2;
         buf = (char *) realloc( buf, bufCap );
      }
      memcpy( buf + bufLen, tmp, got );
      bufLen += got;
      if( bufLen > 1024*1024 ) break;   /* 1 MB cap */
   }
   buf[bufLen] = 0;
   CloseHandle( hRd );
   WaitForSingleObject( pi.hProcess, 200000 );
   CloseHandle( pi.hProcess ); CloseHandle( pi.hThread );

   if( ctx->hPanel && IsWindow( ctx->hPanel ) ) {
      PostMessageA( ctx->hPanel, WM_AI_REPLY, 0, (LPARAM)buf );
   } else {
      free( buf );
   }
   free( ctx );
   return 0;

fail:
   {
      char * err = _strdup( "[curl spawn failed]\n" );
      if( ctx->hPanel && IsWindow( ctx->hPanel ) )
         PostMessageA( ctx->hPanel, WM_AI_APPEND, 0, (LPARAM)err );
      else
         free( err );
   }
   free( ctx );
   return 1;
}
```

- [ ] **Step 4: Add `WM_AI_REPLY` handler — calls `AIDISPATCHREPLY` via `hb_dynsymFindName`**

Insert after the `WM_AI_APPEND` case in `AIPanelWndProc`:

```c
   case WM_AI_REPLY:
      if( lParam ) {
         char * p = (char *) lParam;
         PHB_DYNS pSym = hb_dynsymFindName( "AIDISPATCHREPLY" );
         if( pSym ) {
            hb_vmPushDynSym( pSym );
            hb_vmPushNil();
            hb_vmPushString( p, strlen(p) );
            hb_vmFunction( 1 );
         } else {
            s_aiAppend( "\r\n[AIDispatchReply not registered]\r\n" );
            s_aiAppend( p );
         }
         free( p );
      }
      return 0;
```

- [ ] **Step 5: Build + commit**

```
cd source
build_now.bat
git add source/hbbuilder_win.prg
git commit -m "feat(win-ai): payload builder + curl worker thread

Writes JSON to %TEMP%\hbb_ai_req_<pid>.json, spawns curl.exe with
stdout pipe, ReadFile loop, posts WM_AI_REPLY -> AIDispatchReply (PRG).
Defensive against panel close mid-call via IsWindow check."
```

---

## Task 7: C — wire Send button, Clear button, /key handling, Enter key

**Files:**
- Modify: `source/hbbuilder_win.prg` (inline C dump block)

**Goal:** Hook WM_COMMAND for Send (id 2031), Clear (id 2011). Hook WM_KEYDOWN on input EDIT subclass for Enter. Call `AIDESCRIBEACTIVEFORM` and `AIDESCRIBEDBF` to enrich the user message.

- [ ] **Step 1: Add a helper to call a Harbour function returning a C string copy**

Place above `AIPanelWndProc`:

```c
/* Call Harbour str-returning function. Caller frees with free(). NULL if missing/empty. */
static char * s_aiCallHbStr( const char * fnName, const char * arg )
{
   PHB_DYNS pSym = hb_dynsymFindName( fnName );
   PHB_ITEM pRet;
   if( !pSym ) return NULL;
   hb_vmPushDynSym( pSym );
   hb_vmPushNil();
   if( arg ) { hb_vmPushString( arg, strlen(arg) ); hb_vmFunction( 1 ); }
   else      { hb_vmFunction( 0 ); }
   pRet = hb_stackReturnItem();
   if( pRet && HB_IS_STRING( pRet ) ) {
      const char * s = hb_itemGetCPtr( pRet );
      if( s && *s ) return _strdup( s );
   }
   return NULL;
}
```

- [ ] **Step 2: Add `s_aiOnSend` — runs on UI thread when Send clicked**

```c
static void s_aiOnSend( void )
{
   char prompt[8192], echo[8200], * actCtx, * dbfCtx, model[128], * userMsg, * dbfStart, * dbfEnd, * dbfPath;
   int promptLen, capacity;
   AICTX * ctx;
   BOOL useDeep;
   HANDLE hThread;
   DWORD tid;

   GetWindowTextA( s_hAIInput, prompt, sizeof(prompt) );
   if( prompt[0] == 0 ) return;
   SetWindowTextA( s_hAIInput, "" );

   _snprintf( echo, sizeof(echo), "\r\n> %s\r\n", prompt );
   s_aiAppend( echo );

   /* /key sk-... */
   if( strncmp( prompt, "/key ", 5 ) == 0 ) {
      const char * k = prompt + 5;
      while( *k == ' ' ) k++;
      if( strncmp( k, "sk-", 3 ) == 0 ) {
         s_aiSaveKey( k );
         s_aiAppend( "DeepSeek API key saved.\r\n" );
      } else {
         s_aiAppend( "Invalid key.\r\n" );
      }
      return;
   }

   GetWindowTextA( s_hAICombo, model, sizeof(model) );
   if( model[0] == 0 ) lstrcpynA( model, "codellama", sizeof(model) );
   useDeep = s_aiIsDeepseek( model );
   if( useDeep && (!s_aiDeepseekKey || !*s_aiDeepseekKey) ) {
      s_aiAppend( "\r\nDeepSeek API key not set. Type `/key sk-...` first.\r\n" );
      return;
   }

   /* Build extended user message: prompt + ACTIVE FORM + DBF schema */
   capacity = (int) strlen( prompt ) + 32 * 1024;
   userMsg = (char *) malloc( capacity );
   lstrcpynA( userMsg, prompt, capacity );
   promptLen = (int) strlen( userMsg );

   actCtx = s_aiCallHbStr( "AIDESCRIBEACTIVEFORM", NULL );
   if( actCtx ) {
      _snprintf( userMsg + promptLen, capacity - promptLen,
         "\n\nACTIVE FORM (currently open in the designer): %s\n"
         "If the user mentions any control listed above by its name or text, "
         "those controls ALREADY EXIST — do NOT redefine them in \"controls\". "
         "Only emit \"controls\" for genuinely new ones.\n",
         actCtx );
      promptLen = (int) strlen( userMsg );
      free( actCtx );
   }

   /* Detect *.dbf in prompt */
   dbfStart = strstr( prompt, ".dbf" );
   if( !dbfStart ) dbfStart = strstr( prompt, ".DBF" );
   if( dbfStart ) {
      const char * s = dbfStart;
      while( s > prompt && ( isalnum((unsigned char)s[-1]) || s[-1]=='_' || s[-1]=='/' || s[-1]=='\\' || s[-1]=='.' || s[-1]=='-' ) )
         s--;
      dbfEnd = dbfStart + 4;
      dbfPath = (char *) malloc( (size_t)(dbfEnd - s) + 1 );
      memcpy( dbfPath, s, dbfEnd - s );
      dbfPath[dbfEnd - s] = 0;
      {
         char * schema = s_aiCallHbStr( "AIDESCRIBEDBF", dbfPath );
         if( schema ) {
            _snprintf( userMsg + promptLen, capacity - promptLen,
               "\n\nDBF FIELDS (real schema of %s): %s\n"
               "Use these field names verbatim. Build TLabel + TEdit for each, "
               "plus nav buttons (Prev/Next/Save). Y-step 30, label width 100.\n",
               dbfPath, schema );
            free( schema );
         }
      }
      free( dbfPath );
   }

   ctx = (AICTX *) malloc( sizeof(AICTX) );
   ctx->hPanel = s_hAIWnd;
   {
      char path[MAX_PATH];
      if( !s_aiBuildPayload( useDeep, model, userMsg,
                             s_aiDeepseekKey, ctx->cmdline, sizeof(ctx->cmdline),
                             path, sizeof(path) ) ) {
         s_aiAppend( "\r\n[Payload build failed]\r\n" );
         free( ctx ); free( userMsg ); return;
      }
   }
   free( userMsg );

   SetWindowTextA( s_hAIStatus, "Status: Sending..." );

   hThread = CreateThread( NULL, 0, ai_send_thread, ctx, 0, &tid );
   if( hThread ) CloseHandle( hThread );
   else {
      s_aiAppend( "\r\n[CreateThread failed]\r\n" );
      free( ctx );
   }
}
```

- [ ] **Step 3: Add `s_aiOnClear`**

```c
static void s_aiOnClear( void )
{
   SetWindowTextA( s_hAIOutput, "AI Assistant ready.\r\n" );
}
```

- [ ] **Step 4: Add `WM_COMMAND` dispatch in `AIPanelWndProc`**

Insert before `WM_AI_APPEND`:

```c
   case WM_COMMAND:
      switch( LOWORD(wParam) ) {
         case 2011: s_aiOnClear(); return 0;
         case 2031: s_aiOnSend();  return 0;
      }
      break;
```

- [ ] **Step 5: Subclass the input EDIT to handle Enter key**

Add above `AIPanelWndProc`:

```c
static WNDPROC s_aiInputOldProc = NULL;
static LRESULT CALLBACK s_aiInputProc( HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam )
{
   if( msg == WM_KEYDOWN && wParam == VK_RETURN ) {
      s_aiOnSend();
      return 0;
   }
   if( msg == WM_CHAR && wParam == VK_RETURN ) return 0;  /* swallow beep */
   return CallWindowProc( s_aiInputOldProc, hWnd, msg, wParam, lParam );
}
```

In `W32_AIASSISTANTPANEL`, just after creating `s_hAIInput`:

```c
      s_aiInputOldProc = (WNDPROC) SetWindowLongPtr( s_hAIInput, GWLP_WNDPROC,
                                                     (LONG_PTR) s_aiInputProc );
```

- [ ] **Step 6: Build + commit**

```
cd source
build_now.bat
git add source/hbbuilder_win.prg
git commit -m "feat(win-ai): wire Send/Clear/Enter, /key, active-form + DBF context

Send composes prompt + AIDescribeActiveForm + AIDescribeDbf, validates key
for deepseek models, spawns ai_send_thread. Clear resets chat. Enter in
input subclass triggers Send. /key sk-... saves DeepSeek key inline."
```

---

## Task 8: C — chips bar (`W32_AISetChips` + chip click)

**Files:**
- Modify: `source/hbbuilder_win.prg` (inline C dump block)

**Goal:** PRG hands an array of chip labels; C destroys old chip buttons and creates new ones inside `s_hAIChipsBar`. Clicking a chip puts its text into the input and triggers Send.

- [ ] **Step 1: Add chip helpers**

Above `AIPanelWndProc`:

```c
#define AI_CHIP_ID_BASE 2100
#define AI_CHIP_MAX     8

static char * s_aiChipText[ AI_CHIP_MAX ] = { NULL };
static int    s_aiChipCount = 0;

static void s_aiClearChips( void )
{
   int i;
   HWND hChild;
   for( i = 0; i < AI_CHIP_MAX; i++ ) {
      hChild = GetDlgItem( s_hAIChipsBar, AI_CHIP_ID_BASE + i );
      if( hChild ) DestroyWindow( hChild );
      if( s_aiChipText[i] ) { free( s_aiChipText[i] ); s_aiChipText[i] = NULL; }
   }
   s_aiChipCount = 0;
}

static void s_aiSetChips( const char ** labels, int n )
{
   int i, x = 4, y = 2, w, totalW;
   RECT rc;
   HDC hdc;
   SIZE sz;
   if( !s_hAIChipsBar ) return;
   s_aiClearChips();
   if( n > AI_CHIP_MAX ) n = AI_CHIP_MAX;
   GetClientRect( s_hAIChipsBar, &rc );
   totalW = rc.right - rc.left - 8;
   hdc = GetDC( s_hAIChipsBar );
   SelectObject( hdc, s_hAIUiFont );
   for( i = 0; i < n; i++ ) {
      const char * t = labels[i];
      if( !t || !*t ) continue;
      GetTextExtentPoint32A( hdc, t, (int)strlen(t), &sz );
      w = sz.cx + 18;
      if( x + w > totalW ) break;
      s_aiChipText[ s_aiChipCount ] = _strdup( t );
      CreateWindowExA( 0, "BUTTON", t,
         WS_CHILD|WS_VISIBLE|BS_PUSHBUTTON,
         x, y, w, 24,
         s_hAIChipsBar, (HMENU)(LONG_PTR)(AI_CHIP_ID_BASE + s_aiChipCount),
         GetModuleHandle(NULL), NULL );
      {
         HWND hb = GetDlgItem( s_hAIChipsBar, AI_CHIP_ID_BASE + s_aiChipCount );
         SendMessage( hb, WM_SETFONT, (WPARAM) s_hAIUiFont, TRUE );
      }
      x += w + 4;
      s_aiChipCount++;
   }
   ReleaseDC( s_hAIChipsBar, hdc );
}
```

- [ ] **Step 2: Subclass `s_hAIChipsBar` to forward chip clicks to the panel WndProc**

Add above `AIPanelWndProc`:

```c
static WNDPROC s_aiChipsOldProc = NULL;
static LRESULT CALLBACK s_aiChipsProc( HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam )
{
   if( msg == WM_COMMAND ) {
      WORD id = LOWORD( wParam );
      if( id >= AI_CHIP_ID_BASE && id < AI_CHIP_ID_BASE + AI_CHIP_MAX ) {
         int idx = id - AI_CHIP_ID_BASE;
         if( idx < s_aiChipCount && s_aiChipText[idx] ) {
            SetWindowTextA( s_hAIInput, s_aiChipText[idx] );
            s_aiOnSend();
         }
         return 0;
      }
   }
   return CallWindowProc( s_aiChipsOldProc, hWnd, msg, wParam, lParam );
}
```

In `W32_AIASSISTANTPANEL`, after creating `s_hAIChipsBar`:

```c
      s_aiChipsOldProc = (WNDPROC) SetWindowLongPtr( s_hAIChipsBar, GWLP_WNDPROC,
                                                     (LONG_PTR) s_aiChipsProc );
```

- [ ] **Step 3: Add `HB_FUNC( W32_AISETCHIPS )`**

```c
HB_FUNC( W32_AISETCHIPS )
{
   PHB_ITEM pArr = hb_param( 1, HB_IT_ARRAY );
   int i, n;
   const char ** labels;
   if( !pArr || !s_hAIChipsBar ) return;
   n = (int) hb_arrayLen( pArr );
   if( n > AI_CHIP_MAX ) n = AI_CHIP_MAX;
   labels = (const char **) malloc( sizeof(char *) * (size_t)n );
   for( i = 0; i < n; i++ ) labels[i] = hb_arrayGetCPtr( pArr, i + 1 );
   s_aiSetChips( labels, n );
   free( (void *) labels );
}
```

- [ ] **Step 4: Build + commit**

```
cd source
build_now.bat
git add source/hbbuilder_win.prg
git commit -m "feat(win-ai): suggestion chips bar with click-to-send

W32_AISetChips(aLabels) destroys old chip buttons and creates new ones
sized to text. Click forwards via subclassed chips-bar WndProc into Send."
```

---

## Task 9: C — Ollama probe + auto-install + dynamic model list

**Files:**
- Modify: `source/hbbuilder_win.prg` (inline C dump block)

**Goal:** On panel open, probe `http://localhost:11434/api/tags` via curl. If reachable, replace the hardcoded combo list with DeepSeek items + actual installed models. If Ollama not installed and no DeepSeek key, prompt to install.

- [ ] **Step 1: Add helpers**

Above `AIPanelWndProc`:

```c
/* Run a command, capture stdout to caller-allocated buffer. Returns bytes read. */
static int s_aiRunCapture( const char * cmd, char * out, int outMax, DWORD timeoutMs )
{
   HANDLE hRd = NULL, hWr = NULL;
   SECURITY_ATTRIBUTES sa;
   STARTUPINFOA si;
   PROCESS_INFORMATION pi;
   DWORD got, total = 0;
   char tmp[4096];
   char cmdBuf[2048];

   sa.nLength = sizeof(sa); sa.bInheritHandle = TRUE; sa.lpSecurityDescriptor = NULL;
   if( !CreatePipe( &hRd, &hWr, &sa, 0 ) ) return 0;
   SetHandleInformation( hRd, HANDLE_FLAG_INHERIT, 0 );

   memset( &si, 0, sizeof(si) );
   si.cb = sizeof(si);
   si.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
   si.hStdOutput = hWr;
   si.hStdError  = hWr;
   si.hStdInput  = GetStdHandle( STD_INPUT_HANDLE );
   si.wShowWindow = SW_HIDE;

   lstrcpynA( cmdBuf, cmd, sizeof(cmdBuf) );
   if( !CreateProcessA( NULL, cmdBuf, NULL, NULL, TRUE,
                        CREATE_NO_WINDOW, NULL, NULL, &si, &pi ) ) {
      CloseHandle(hRd); CloseHandle(hWr); return 0;
   }
   CloseHandle( hWr );

   while( total + 1 < (DWORD)outMax &&
          ReadFile( hRd, tmp, sizeof(tmp), &got, NULL ) && got > 0 ) {
      DWORD copy = got;
      if( total + copy + 1 > (DWORD)outMax ) copy = outMax - 1 - total;
      memcpy( out + total, tmp, copy );
      total += copy;
   }
   out[total] = 0;
   CloseHandle( hRd );
   WaitForSingleObject( pi.hProcess, timeoutMs );
   CloseHandle( pi.hProcess ); CloseHandle( pi.hThread );
   return (int) total;
}

static BOOL s_aiOllamaInstalled( void )
{
   char buf[1024];
   int n = s_aiRunCapture( "where ollama", buf, sizeof(buf), 2000 );
   return n > 0 && strstr( buf, "ollama" ) != NULL;
}

static BOOL s_aiTryStartOllama( void )
{
   ShellExecuteA( NULL, "open", "ollama", "serve", NULL, SW_HIDE );
   /* Brief wait for daemon */
   {
      int i;
      char buf[256];
      for( i = 0; i < 10; i++ ) {
         Sleep( 300 );
         if( s_aiRunCapture(
              "curl.exe -s -m 1 http://localhost:11434/api/tags",
              buf, sizeof(buf), 2000 ) > 0 &&
             strstr( buf, "models" ) ) return TRUE;
      }
   }
   return FALSE;
}

/* Returns a heap buffer with the /api/tags JSON, or NULL if unreachable. */
static char * s_aiFetchOllamaTags( void )
{
   char * buf = (char *) malloc( 16384 );
   int n = s_aiRunCapture(
      "curl.exe -s -m 2 http://localhost:11434/api/tags",
      buf, 16384, 3000 );
   if( n > 0 && strstr( buf, "models" ) ) return buf;
   free( buf );
   return NULL;
}
```

- [ ] **Step 2: Repopulate combo from tags by calling `AIPARSEOLLAMATAGS` (PRG-side parser, defined in Task 13)**

Add to `W32_AIASSISTANTPANEL`, after the hardcoded `CB_ADDSTRING` calls:

```c
      /* Replace hardcoded list with DeepSeek + actual Ollama tags */
      {
         char * tags = s_aiFetchOllamaTags();
         if( tags ) {
            PHB_DYNS pSym = hb_dynsymFindName( "AIPARSEOLLAMATAGS" );
            if( pSym ) {
               PHB_ITEM pRet;
               hb_vmPushDynSym( pSym );
               hb_vmPushNil();
               hb_vmPushString( tags, strlen(tags) );
               hb_vmFunction( 1 );
               pRet = hb_stackReturnItem();
               if( pRet && HB_IS_ARRAY( pRet ) ) {
                  HB_SIZE i, n = hb_arrayLen( pRet );
                  SendMessage( s_hAICombo, CB_RESETCONTENT, 0, 0 );
                  if( s_aiDeepseekKey ) {
                     SendMessageA( s_hAICombo, CB_ADDSTRING, 0, (LPARAM)"deepseek-v4-flash" );
                     SendMessageA( s_hAICombo, CB_ADDSTRING, 0, (LPARAM)"deepseek-chat" );
                  }
                  for( i = 1; i <= n; i++ ) {
                     const char * m = hb_arrayGetCPtr( pRet, i );
                     if( m && *m )
                        SendMessageA( s_hAICombo, CB_ADDSTRING, 0, (LPARAM)m );
                  }
                  SendMessage( s_hAICombo, CB_SETCURSEL, 0, 0 );
               }
            }
            free( tags );
         } else if( s_aiOllamaInstalled() ) {
            /* Ollama installed but daemon down or no models. Try to start. */
            BOOL up = s_aiTryStartOllama();
            if( up ) {
               char * tags2 = s_aiFetchOllamaTags();
               if( tags2 ) {
                  /* If there are zero models, kick off background pull of default */
                  if( !strstr( tags2, "\"name\"" ) ) {
                     s_aiAppend( "No models installed. Pulling default model gemma3...\r\n" );
                     {
                        STARTUPINFOA si2 = {0};
                        PROCESS_INFORMATION pi2 = {0};
                        char cmd[256];
                        si2.cb = sizeof(si2);
                        si2.dwFlags = STARTF_USESHOWWINDOW;
                        si2.wShowWindow = SW_HIDE;
                        lstrcpynA( cmd, "ollama pull gemma3", sizeof(cmd) );
                        if( CreateProcessA( NULL, cmd, NULL, NULL, FALSE,
                                            CREATE_NO_WINDOW, NULL, NULL, &si2, &pi2 ) ) {
                           CloseHandle( pi2.hProcess ); CloseHandle( pi2.hThread );
                        }
                     }
                  }
                  free( tags2 );
               }
            } else {
               s_aiAppend( "Ollama installed but daemon not reachable. "
                           "Run `ollama serve` in a terminal.\r\n" );
            }
         } else if( !s_aiDeepseekKey ) {
            /* Neither backend available — prompt to install Ollama */
            int r = MessageBoxA( s_hAIWnd,
               "Ollama is not installed.\n\n"
               "The AI Assistant needs Ollama (local LLMs) or a DeepSeek API key.\n\n"
               "Open the Ollama download page now?",
               "AI Assistant — backend missing",
               MB_YESNO | MB_ICONINFORMATION );
            if( r == IDYES ) {
               ShellExecuteA( NULL, "open",
                  "https://ollama.com/download", NULL, NULL, SW_SHOW );
               s_aiAppend( "Opened https://ollama.com/download. "
                           "Reopen this panel after install.\r\n" );
            }
         }
      }
```

- [ ] **Step 3: Build + commit**

```
cd source
build_now.bat
git add source/hbbuilder_win.prg
git commit -m "feat(win-ai): dynamic Ollama model list + missing-backend prompt

Probes localhost:11434/api/tags via curl, parses via AIParseOllamaTags
(PRG). If neither Ollama installed nor DeepSeek key, MessageBox
offers download page."
```

---

## Task 10: PRG — port `AIRunProject`, `AIDescribeDbf`, `AIDescribeActiveForm`, `AIGetActiveFormClass`

**Files:**
- Modify: `source/hbbuilder_win.prg`
- Read-only reference: `source/hbbuilder_macos.prg:4901-5050`

**Goal:** Add the four data-introspection helpers. They use only platform-neutral Harbour functions plus `UI_GetProp`, `UI_GetChildCount`, `UI_GetChild` (all already on Win32).

- [ ] **Step 1: Locate the existing `static function ShowAIAssistant()` in `hbbuilder_win.prg` (around line 5493)**

Just below it (still in the `// === AI Assistant ===` section), add the four functions copied verbatim from `hbbuilder_macos.prg:4901-5050`.

- [ ] **Step 2: Paste these (no edits)**

```harbour
// AIRunProject() - public wrapper called from C when LLM emits {"action":"run"}
function AIRunProject()
   TBRun()
return nil

// AIResizeForm( nW, nH ) - resize current design form to given size.
function AIResizeForm( nW, nH )
   local hForm
   if oDesignForm == nil
      return nil
   endif
   hForm := oDesignForm:hCpp
   if HB_ISNUMERIC( nW ) .and. nW > 50
      UI_SetProp( hForm, "nWidth",  nW )
   endif
   if HB_ISNUMERIC( nH ) .and. nH > 50
      UI_SetProp( hForm, "nHeight", nH )
   endif
   InspectorRefresh( hForm )
   SyncDesignerToCode()
return nil

// AIFitForm() - resize current form to fit all its child controls.
function AIFitForm()
   local hForm, nCount, i, hCtrl, nMaxR := 0, nMaxB := 0, nR, nB
   if oDesignForm == nil
      return nil
   endif
   hForm := oDesignForm:hCpp
   nCount := UI_GetChildCount( hForm )
   for i := 1 to nCount
      hCtrl := UI_GetChild( hForm, i )
      if hCtrl == 0
         loop
      endif
      nR := UI_GetProp( hCtrl, "nLeft" ) + UI_GetProp( hCtrl, "nWidth" )
      nB := UI_GetProp( hCtrl, "nTop" )  + UI_GetProp( hCtrl, "nHeight" )
      if nR > nMaxR; nMaxR := nR; endif
      if nB > nMaxB; nMaxB := nB; endif
   next
   if nMaxR > 0
      UI_SetProp( hForm, "nWidth",  nMaxR + 30 )
   endif
   if nMaxB > 0
      UI_SetProp( hForm, "nHeight", nMaxB + 60 )
   endif
   InspectorRefresh( hForm )
   SyncDesignerToCode()
return nil

function AIDescribeDbf( cPath )
   local aStruct, i, cJson, hField
   local aFields := {}
   local cTried := cPath
   local oErr

   if ! HB_ISCHAR( cPath ) .or. Empty( cPath )
      return ""
   endif

   if ! File( cTried )
      cTried := hb_DirBase() + cPath
      if ! File( cTried )
         cTried := "./" + cPath
      endif
   endif
   if ! File( cTried )
      return ""
   endif

   begin sequence with { | e | break( e ) }
      dbUseArea( .T., , cTried, "AIDESCRIBE_TMP", .T., .T. )
      aStruct := dbStruct()
      dbCloseArea()
   recover using oErr
      aStruct := nil
   end sequence

   if aStruct == nil .or. ! HB_ISARRAY( aStruct )
      return ""
   endif

   for i := 1 to Len( aStruct )
      hField := { => }
      hField[ "name" ] := aStruct[i][1]
      hField[ "type" ] := aStruct[i][2]
      hField[ "len"  ] := aStruct[i][3]
      hField[ "dec"  ] := aStruct[i][4]
      AAdd( aFields, hField )
   next

   cJson := hb_jsonEncode( aFields )
return cJson

function AIDescribeActiveForm()
   local hForm, hSpec, aCtrls := {}, hCtrl, hChild, i, nCount, cType, cName
   if oDesignForm == nil
      return ""
   endif
   hForm := oDesignForm:hCpp
   hSpec := { => }
   hSpec[ "class" ] := AIGetActiveFormClass()
   hSpec[ "title" ] := UI_GetProp( hForm, "cText" )
   hSpec[ "w"     ] := UI_GetProp( hForm, "nWidth"  )
   hSpec[ "h"     ] := UI_GetProp( hForm, "nHeight" )
   nCount := UI_GetChildCount( hForm )
   for i := 1 to nCount
      hChild := UI_GetChild( hForm, i )
      if hChild == 0
         loop
      endif
      cName := UI_GetProp( hChild, "cName" )
      if Empty( cName )
         loop
      endif
      cType := UI_GetProp( hChild, "cClassName" )
      if Empty( cType )
         cType := "T?"
      endif
      hCtrl := { => }
      hCtrl[ "type" ] := cType
      hCtrl[ "name" ] := cName
      hCtrl[ "x"    ] := UI_GetProp( hChild, "nLeft"   )
      hCtrl[ "y"    ] := UI_GetProp( hChild, "nTop"    )
      hCtrl[ "w"    ] := UI_GetProp( hChild, "nWidth"  )
      hCtrl[ "h"    ] := UI_GetProp( hChild, "nHeight" )
      hCtrl[ "text" ] := UI_GetProp( hChild, "cText"   )
      AAdd( aCtrls, hCtrl )
   next
   hSpec[ "controls" ] := aCtrls
return hb_jsonEncode( hSpec )

function AIGetActiveFormClass()
   local cName
   if oDesignForm == nil .or. nActiveForm == nil .or. nActiveForm < 1 .or. ;
      nActiveForm > Len( aForms )
      return ""
   endif
   cName := aForms[ nActiveForm ][ 1 ]
   if Empty( cName )
      return ""
   endif
return "T" + cName
```

- [ ] **Step 3: Verify Win32 globals exist (`oDesignForm`, `aForms`, `nActiveForm`)**

```
grep -n "static oDesignForm\|static aForms\|static nActiveForm" source/hbbuilder_win.prg
```

Expected: all three present (they were already declared near line 24, line ~25, line ~27).

- [ ] **Step 4: Build + smoke**

```
cd source
build_now.bat
```

Expected: clean. Note that no PRG side calls these yet — they will be called from C in Task 7's `s_aiOnSend` (already wired), so opening the panel and clicking Send (with Ollama not running) should produce no errors aside from a network failure shown in chat.

- [ ] **Step 5: Commit**

```
git add source/hbbuilder_win.prg
git commit -m "feat(win-ai): port introspection helpers from macOS

AIRunProject, AIResizeForm, AIFitForm, AIDescribeDbf, AIDescribeActiveForm,
AIGetActiveFormClass — verbatim from hbbuilder_macos.prg. All use
platform-neutral UI_GetProp/UI_GetChild already present on Win32."
```

---

## Task 11: PRG — port `AI_FindCtrlByName`, `AI_RewriteClassName`, `AIAddCode`

**Files:**
- Modify: `source/hbbuilder_win.prg`
- Read-only reference: `source/hbbuilder_macos.prg:5057-5133`

**Goal:** Add the code-injection helper. Uses `CodeEditor*` and `SyncDesignerToCode` (already on Win).

- [ ] **Step 1: Append after the four helpers added in Task 10**

```harbour
static function AI_FindCtrlByName( hForm, cName )
   local i, nCount, hChild
   if Empty( cName ) .or. hForm == 0
      return 0
   endif
   nCount := UI_GetChildCount( hForm )
   for i := 1 to nCount
      hChild := UI_GetChild( hForm, i )
      if hChild != 0 .and. UI_GetProp( hChild, "cName" ) == cName
         return hChild
      endif
   next
return 0

static function AI_RewriteClassName( cCode, cNew )
   local cResult := "", nPos, nEnd, cChar, nLen
   nLen := Len( cCode )
   nPos := 1
   do while nPos <= nLen
      nEnd := hb_At( "CLASS T", cCode, nPos )
      if nEnd == 0
         cResult += SubStr( cCode, nPos )
         exit
      endif
      cResult += SubStr( cCode, nPos, nEnd - nPos ) + "CLASS " + cNew
      nPos := nEnd + 7
      do while nPos <= nLen
         cChar := SubStr( cCode, nPos, 1 )
         if ! ( ( cChar >= "A" .and. cChar <= "Z" ) .or. ;
                ( cChar >= "a" .and. cChar <= "z" ) .or. ;
                ( cChar >= "0" .and. cChar <= "9" ) .or. ;
                cChar == "_" )
            exit
         endif
         nPos++
      enddo
   enddo
return cResult

function AIAddCode( cCode )
   local cExisting, cNew, nTab, nFromLine, nToLine, cActiveCls
   if ! HB_ISCHAR( cCode ) .or. Empty( cCode )
      return nil
   endif
   nTab := CodeEditorGetActiveTab( hCodeEditor )
   if nTab < 1
      return nil
   endif
   cActiveCls := AIGetActiveFormClass()
   if ! Empty( cActiveCls )
      cCode := AI_RewriteClassName( cCode, cActiveCls )
   endif
   cExisting := CodeEditorGetText2( hCodeEditor, nTab )
   if ! HB_ISCHAR( cExisting )
      cExisting := ""
   endif
   if ! ( Right( cExisting, 1 ) == Chr(10) )
      cExisting += Chr(10)
   endif
   nFromLine := Len( hb_ATokens( cExisting + Chr(10), Chr(10) ) ) - 2
   cNew := cExisting + Chr(10) + cCode + Chr(10)
   CodeEditorSetTabText( hCodeEditor, nTab, cNew )
   nToLine := Len( hb_ATokens( cNew, Chr(10) ) ) - 2
   CodeEditorClearMarks( hCodeEditor )
   CodeEditorMarkLines( hCodeEditor, nFromLine, nToLine, 32896 )
   SyncDesignerToCode()
return nil
```

- [ ] **Step 2: Verify referenced functions exist on Win32**

```
grep -n "function CodeEditorGetActiveTab\|function CodeEditorGetText2\|function CodeEditorSetTabText\|function CodeEditorClearMarks\|function CodeEditorMarkLines\|function SyncDesignerToCode" source/hbbuilder_win.prg
```

Expected: all six present.

- [ ] **Step 3: Build + commit**

```
cd source
build_now.bat
git add source/hbbuilder_win.prg
git commit -m "feat(win-ai): port AIAddCode + class rewriter

Appends LLM-emitted code to active .prg tab with green line marker.
Rewrites stale CLASS TFormN to active class (defensive against few-shot
drift). Verbatim port of macOS impl."
```

---

## Task 12: PRG — port `AIBuildForm`

**Files:**
- Modify: `source/hbbuilder_win.prg`
- Read-only reference: `source/hbbuilder_macos.prg:5137-5278`

**Goal:** Add the form generator / upserter. Calls Win32-side `MenuNewForm`, `UI_*New`, `UI_FormRealizeChildren`, `InspectorPopulateCombo`, `InspectorRefresh`, `SyncDesignerToCode` (all present on Win).

- [ ] **Step 1: Verify referenced UI_*New functions exist on Win32**

```
grep -n "HB_FUNC( UI_LABELNEW\|HB_FUNC( UI_EDITNEW\|HB_FUNC( UI_BUTTONNEW\|HB_FUNC( UI_FORMREALIZECHILDREN" source/hbbuilder_win.prg source/cpp/*.cpp
```

Expected: present. If `UI_FormRealizeChildren` is macOS-only (it materializes lazy NSViews), it can be replaced by a no-op call or removed — Win32 creates HWNDs eagerly. Probe behavior:

```
grep -n "UI_FORMREALIZECHILDREN\|UI_FormRealizeChildren" source/hbbuilder_win.prg source/cpp/*.cpp
```

If absent on Win32, **edit the pasted `AIBuildForm` to remove the `UI_FormRealizeChildren( hForm )` line** (it is a Cocoa-only need).

- [ ] **Step 2: Append `AIBuildForm` verbatim from `hbbuilder_macos.prg:5137-5278`**

(See macOS source — no transcription here other than the conditional `UI_FormRealizeChildren` removal noted above.)

- [ ] **Step 3: Build + commit**

```
cd source
build_now.bat
git add source/hbbuilder_win.prg
git commit -m "feat(win-ai): port AIBuildForm — form codegen + upsert

Decodes JSON spec, dispatches new vs current vs resize by shape.
Upserts existing controls by name (move/resize/relabel/items) instead
of duplicating. Drops macOS-only UI_FormRealizeChildren call."
```

---

## Task 13: PRG — `AIDispatchReply`, `AIDefaultChips`, `AIParseOllamaTags`

**Files:**
- Modify: `source/hbbuilder_win.prg`

**Goal:** New on Win (Mac dispatches in Obj-C; Linux dispatches in python helper). Win does it in PRG using `hb_jsonDecode` + balanced-brace recovery.

- [ ] **Step 1: Append `AIDispatchReply`**

```harbour
// AIDispatchReply( cRaw ) - called from C with raw HTTP reply JSON.
// Extracts the model's "content" string, then parses it as our skill JSON
// and dispatches to AIBuildForm / AIAddCode / AIRunProject / chat.
function AIDispatchReply( cRaw )
   local hOuter, cReply, cTrim, hSpec, oErr
   local cAction, cText, cCode
   local nStart, nEnd, nDepth, lInStr, lEsc, i, c
   local aNext

   if ! HB_ISCHAR( cRaw ) .or. Empty( cRaw )
      return nil
   endif

   // 1. Extract assistant content string from OpenAI / Ollama / DeepSeek shape
   begin sequence with { | e | break( e ) }
      hOuter := hb_jsonDecode( cRaw )
   recover using oErr
      hOuter := nil
   end sequence

   cReply := nil
   if HB_ISHASH( hOuter )
      if HB_ISARRAY( hOuter[ "choices" ] ) .and. Len( hOuter[ "choices" ] ) > 0
         if HB_ISHASH( hOuter[ "choices" ][1] ) .and. HB_ISHASH( hOuter[ "choices" ][1][ "message" ] )
            cReply := hOuter[ "choices" ][1][ "message" ][ "content" ]
         endif
      endif
      if cReply == nil .and. HB_ISHASH( hOuter[ "message" ] )
         cReply := hOuter[ "message" ][ "content" ]
      endif
      if cReply == nil .and. HB_ISHASH( hOuter[ "error" ] ) .and. ;
         HB_ISCHAR( hOuter[ "error" ][ "message" ] )
         W32_AIAppendChat( Chr(10) + "[API error: " + hOuter[ "error" ][ "message" ] + "]" + Chr(10) )
         return nil
      endif
   endif

   if cReply == nil .or. ! HB_ISCHAR( cReply ) .or. Empty( cReply )
      W32_AIAppendChat( Chr(10) + "[Empty response]" + Chr(10) )
      return nil
   endif

   cTrim := AllTrim( cReply )

   // Strip ```json ... ``` fences
   if Left( cTrim, 3 ) == "```"
      i := At( Chr(10), cTrim )
      if i > 0
         cTrim := SubStr( cTrim, i + 1 )
      endif
      if Right( cTrim, 3 ) == "```"
         cTrim := Left( cTrim, Len( cTrim ) - 3 )
      endif
      cTrim := AllTrim( cTrim )
   endif

   // 2. Try direct JSON parse of the assistant message
   hSpec := nil
   if Left( cTrim, 1 ) == "{"
      begin sequence with { | e | break( e ) }
         hSpec := hb_jsonDecode( cTrim )
      recover using oErr
         hSpec := nil
      end sequence
   endif

   // 3. Balanced-brace recovery if first parse failed
   if ! HB_ISHASH( hSpec ) .and. Left( cTrim, 1 ) == "{"
      nStart := 0; nEnd := 0; nDepth := 0; lInStr := .F.; lEsc := .F.
      for i := 1 to Len( cTrim )
         c := SubStr( cTrim, i, 1 )
         if lInStr
            if lEsc
               lEsc := .F.
            elseif c == "\"
               lEsc := .T.
            elseif c == '"'
               lInStr := .F.
            endif
         elseif c == '"'
            lInStr := .T.
         elseif c == "{"
            if nStart == 0; nStart := i; endif
            nDepth++
         elseif c == "}"
            nDepth--
            if nDepth == 0 .and. nStart > 0
               nEnd := i; exit
            endif
         endif
      next
      if nStart > 0 .and. nEnd > nStart
         begin sequence with { | e | break( e ) }
            hSpec := hb_jsonDecode( SubStr( cTrim, nStart, nEnd - nStart + 1 ) )
         recover using oErr
            hSpec := nil
         end sequence
      endif
   endif

   // 4. Dispatch by shape
   if HB_ISHASH( hSpec )
      cAction := iif( "action" $ hSpec .and. HB_ISCHAR( hSpec[ "action" ] ), hSpec[ "action" ], "" )

      if cAction == "run" .or. cAction == "build_run"
         W32_AIAppendChat( Chr(10) + "Building and running project..." + Chr(10) )
         AIRunProject()
      elseif cAction == "add_code"
         cCode := iif( "code" $ hSpec .and. HB_ISCHAR( hSpec[ "code" ] ), hSpec[ "code" ], "" )
         if Empty( cCode )
            W32_AIAppendChat( Chr(10) + "[add_code: missing code field]" + Chr(10) )
         else
            W32_AIAppendChat( Chr(10) + "Adding code to current form..." + Chr(10) + ;
                              "```harbour" + Chr(10) + cCode + Chr(10) + "```" + Chr(10) )
            AIAddCode( cCode )
            W32_AIAppendChat( "Code appended to active editor tab." + Chr(10) )
         endif
      elseif "controls" $ hSpec .or. "w" $ hSpec .or. "h" $ hSpec .or. "title" $ hSpec
         W32_AIAppendChat( Chr(10) + "Building form..." + Chr(10) )
         AIBuildForm( cTrim )
         W32_AIAppendChat( "Form built — see design view." + Chr(10) )
         if "code" $ hSpec .and. HB_ISCHAR( hSpec[ "code" ] ) .and. ! Empty( hSpec[ "code" ] )
            W32_AIAppendChat( "Adding event handler code..." + Chr(10) + ;
                              "```harbour" + Chr(10) + hSpec[ "code" ] + Chr(10) + "```" + Chr(10) )
            AIAddCode( hSpec[ "code" ] )
         endif
      elseif "text" $ hSpec .and. HB_ISCHAR( hSpec[ "text" ] )
         W32_AIAppendChat( Chr(10) + hSpec[ "text" ] + Chr(10) )
      else
         W32_AIAppendChat( Chr(10) + cReply + Chr(10) )
      endif

      // Suggestion chips from "next" array
      if "next" $ hSpec .and. HB_ISARRAY( hSpec[ "next" ] ) .and. Len( hSpec[ "next" ] ) > 0
         aNext := {}
         for i := 1 to Len( hSpec[ "next" ] )
            if HB_ISCHAR( hSpec[ "next" ][i] ) .and. ! Empty( hSpec[ "next" ][i] )
               AAdd( aNext, hSpec[ "next" ][i] )
            endif
         next
         if Len( aNext ) > 0
            W32_AISetChips( aNext )
         else
            W32_AISetChips( AIDefaultChips() )
         endif
      else
         W32_AISetChips( AIDefaultChips() )
      endif
   else
      // Plain chat (non-JSON reply)
      W32_AIAppendChat( Chr(10) + cReply + Chr(10) )
      W32_AISetChips( AIDefaultChips() )
   endif

   SetStatusBarText( "Status: Ready" )
return nil

function AIDefaultChips()
   if ! Empty( AIGetActiveFormClass() )
      return { "añade ok y cancel", "centralos", "ajusta tamaño form", "run" }
   endif
return { "haz un login", "haz un signup", "form de búsqueda", "run" }

// AIParseOllamaTags( cJson ) - extract array of model names from /api/tags reply.
function AIParseOllamaTags( cJson )
   local hOuter, aNames := {}, aMods, hMod, i, oErr
   if ! HB_ISCHAR( cJson ) .or. Empty( cJson )
      return aNames
   endif
   begin sequence with { | e | break( e ) }
      hOuter := hb_jsonDecode( cJson )
   recover using oErr
      hOuter := nil
   end sequence
   if HB_ISHASH( hOuter ) .and. HB_ISARRAY( hOuter[ "models" ] )
      aMods := hOuter[ "models" ]
      for i := 1 to Len( aMods )
         hMod := aMods[i]
         if HB_ISHASH( hMod ) .and. HB_ISCHAR( hMod[ "name" ] )
            AAdd( aNames, hMod[ "name" ] )
         endif
      next
   endif
return aNames
```

- [ ] **Step 2: Replace `SetStatusBarText` if it does not exist on Win32**

```
grep -n "function SetStatusBarText\|HB_FUNC( SETSTATUSBARTEXT" source/hbbuilder_win.prg
```

If absent: remove the `SetStatusBarText( "Status: Ready" )` line at the end of `AIDispatchReply`. The status update can happen in C from the `WM_AI_REPLY` handler instead — add `SetWindowTextA( s_hAIStatus, "Status: Ready" );` in `AIPanelWndProc`'s `WM_AI_REPLY` case.

- [ ] **Step 3: Build + commit**

```
cd source
build_now.bat
git add source/hbbuilder_win.prg
git commit -m "feat(win-ai): AIDispatchReply + AIDefaultChips + AIParseOllamaTags

Win32-only: parse LLM reply via hb_jsonDecode with balanced-brace
recovery, dispatch to AIBuildForm/AIAddCode/AIRunProject by shape.
Default chips depend on active-form presence. Tag parser feeds combo."
```

---

## Task 14: PRG — `ShowAIAssistant` curl-presence probe

**Files:**
- Modify: `source/hbbuilder_win.prg:5493-5516` (existing stub)

**Goal:** Replace the existing Ollama-curl-probe-then-MsgInfo body with a curl.exe presence check. Panel itself probes Ollama; this function only guards against curl missing.

- [ ] **Step 1: Replace the body of `static function ShowAIAssistant()`**

Replace lines 5493-5516 with:

```harbour
// === AI Assistant ===

static function ShowAIAssistant()
   local cWhere := W32_ShellExec( 'where curl.exe' )

   if Empty( cWhere ) .or. ! ( "curl.exe" $ Lower( cWhere ) )
      MsgInfo( "curl.exe is not available." + Chr(10) + ;
               Chr(10) + ;
               "The AI Assistant requires curl, which ships with Windows 10 1803+." + Chr(10) + ;
               Chr(10) + ;
               "Update Windows or install curl from https://curl.se/windows/", ;
               "curl.exe Not Found" )
      return nil
   endif

   W32_AIAssistantPanel()

return nil
```

- [ ] **Step 2: Build + commit**

```
cd source
build_now.bat
git add source/hbbuilder_win.prg
git commit -m "feat(win-ai): ShowAIAssistant gates on curl.exe presence

Backend probes (Ollama running, DeepSeek key) moved into the panel itself.
This function only checks that curl.exe is on PATH — the only hard
prerequisite that prevents the panel from working at all."
```

---

## Task 15: smoke test — full happy path

**Files:** none modified.

**Goal:** Manual verification of all six core flows end-to-end.

- [ ] **Step 1: Clean build**

```
cd source
build_now.bat
```

Expected: every line ending in `OK`, final `LINK OK`.

- [ ] **Step 2: Run executable**

```
bin\hbbuilder_win.exe
```

- [ ] **Step 3: Panel opens cleanly**

Tools menu → AI Assistant. Panel appears top-right. Dark mode if system in dark mode. Close via X. Reopen — same panel.

- [ ] **Step 4: Smoke without Ollama, without DeepSeek key**

Type "hello" → Send. Chat shows "[curl spawn failed]" or curl error from Ollama unreachable. No crash.

- [ ] **Step 5: Smoke with `/key sk-...` (test mode — does not need a real key for crash safety)**

Type `/key sk-test1234567890`. Expected chat: "DeepSeek API key saved." Combo shows DeepSeek items at top after panel reopen. File `%USERPROFILE%\.hbbuilder_deepseek_key` exists with the key.

Type "hello" → Send with deepseek-v4-flash selected. Expected: API error reply ("invalid API key") shown in chat — which proves the full request/response loop works.

Delete `%USERPROFILE%\.hbbuilder_deepseek_key` afterward to avoid a junk file.

- [ ] **Step 6: Smoke with Ollama running and codellama installed**

Start `ollama serve`; `ollama pull codellama` if missing.

In panel: select `codellama`. Type "haz un login" → Send. Within 5-30s a TForm with login controls appears. Verify upsert: type "centralos" → buttons reposition without duplicates. Type "run" → project builds and launches.

- [ ] **Step 7: Smoke `add_code`**

Type "añade la función fibonacci" → Send. Expected: code appended to active .prg tab with green-mark highlight. Tab re-renders.

- [ ] **Step 8: Close panel during a request**

Type "hello" → Send → immediately close panel (X). Wait for the curl call to finish (≤200s). No crash. Reopen panel — fresh state.

- [ ] **Step 9: Commit verification result**

If all 8 smokes pass:

```
git commit --allow-empty -m "test(win-ai): full smoke suite passes

Panel opens, /key persists, Ollama/codellama round-trip works for
FORM/RUN/ADD_CODE flows, close-during-request safe, dark mode honoured."
```

If a smoke fails: open new task to fix the specific failure; do not claim done.

---

## Task 16: docs and changelog

**Files:**
- Modify: `MEMORY.md` (auto-memory) — add entry pointing to spec + plan if user asks; otherwise skip.

**Goal:** Note completion in project memory if appropriate, and inform user.

- [ ] **Step 1: Skip unless user asks for memory entry**

Per memory rules, do not save derivable codebase facts. Skip this task if the user does not request it.

- [ ] **Step 2: Final summary to user**

Report: "Win32 AI Assistant ported. 14 PRG functions + ~700 LoC C added. Smoke suite passes. Ready to push."

---

## Self-review notes (already applied)

- All `UI_FormRealizeChildren` references guarded in Task 12 (Cocoa-only).
- `SetStatusBarText` substitution path documented in Task 13 step 2.
- Skill prompt verbatim with single semantic edit (Cocoa→Win32 tab name) — no other behavior changes from Mac.
- Worker thread frees buffer if `IsWindow(hPanel)` false — no leak on panel-close-mid-call.
- 1 MB cap on reply buffer prevents OOM if curl streams something huge.
- BCC32 C89 strictness honored — every step keeps decls at top of block.
