# Socket-Based Debugger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the broken .hrb in-process debugger with a socket-based debugger where the user's app runs as a separate native process and communicates with the IDE via TCP localhost.

**Architecture:** The IDE compiles the user's project as a native executable (same as Run/F9) but injects a `dbgclient.prg` module. At startup the user app connects to the IDE's TCP server (port 19800). The debug hook sends PAUSE messages on each source line and waits for IDE commands (STEP, GO, QUIT, etc.). The IDE receives pause notifications, displays position/locals/stack, and sends commands via the socket.

**Tech Stack:** Harbour sockets (`hb_socket*` from hbsocket.h), Harbour debug API (`hb_dbg_SetEntry` from hbapidbg.h), Cocoa TCP server via `CFSocket`/`NSFileHandle`, existing debug panel UI.

---

### Task 1: Create dbgclient.prg — the debug client module

This is a standalone Harbour source file that gets compiled INTO the user's executable. It installs a debug hook and communicates with the IDE over TCP.

**Files:**
- Create: `harbour/dbgclient.prg`

- [ ] **Step 1: Write dbgclient.prg**

```harbour
// dbgclient.prg — Socket-based debug client for HbBuilder
// Included in the user's executable when compiled in debug mode.
// Connects to the IDE's TCP server and sends PAUSE/LOCALS/STACK messages.
// Receives STEP/STEPOVER/GO/QUIT/GETLOCALS/GETSTACK commands.

#include "hbsocket.ch"

static s_hSocket := NIL
static s_lConnected := .F.
static s_cModule := ""

function DbgClientStart( nPort )

   local hSocket, cAddr

   if nPort == nil; nPort := 19800; endif

   hb_socketInit()

   hSocket := hb_socketOpen()
   if hSocket == -1
      return .f.
   endif

   if ! hb_socketConnect( hSocket, { HB_SOCKET_AF_INET, "127.0.0.1", nPort } )
      hb_socketClose( hSocket )
      return .f.
   endif

   s_hSocket := hSocket
   s_lConnected := .t.

   // Install debug hook
   __dbgSetEntry( { |nMode, nLine, cName, nIndex, xFrame| ;
      DbgHook( nMode, nLine, cName, nIndex, xFrame ) } )

   // Send hello
   DbgSend( "HELLO " + ProcFile(1) )

return .t.

static function DbgHook( nMode, nLine, cName, nIndex, xFrame )

   local cCmd

   HB_SYMBOL_UNUSED( nIndex )
   HB_SYMBOL_UNUSED( xFrame )

   if ! s_lConnected
      return
   endif

   // Mode 1: module name change
   if nMode == 1 .and. cName != nil
      s_cModule := cName
      return
   endif

   // Mode 5: source line
   if nMode != 5
      return
   endif

   // Send PAUSE and wait for command
   DbgSend( "PAUSE " + s_cModule + ":" + LTrim( Str( nLine ) ) )

   // Wait for IDE command
   do while s_lConnected
      cCmd := DbgRecv()
      if cCmd == nil .or. Left( cCmd, 4 ) == "QUIT"
         s_lConnected := .f.
         hb_socketClose( s_hSocket )
         QUIT
         return
      endif

      if Left( cCmd, 4 ) == "STEP" .or. Left( cCmd, 2 ) == "GO"
         exit  // continue execution
      endif

      if Left( cCmd, 9 ) == "GETLOCALS"
         DbgSendLocals( nLine )
      elseif Left( cCmd, 8 ) == "GETSTACK"
         DbgSendStack()
      endif
   enddo

return

static function DbgSendLocals( nLine )

   local i, cName, xVal, cType, cOut

   HB_SYMBOL_UNUSED( nLine )

   cOut := "LOCALS"
   for i := 1 to 30
      cName := __dbgVarLName( 1, i )
      if Empty( cName ); exit; endif
      xVal  := __dbgVarLGet( 1, i )
      cType := ValType( xVal )
      cOut += " " + cName + "=" + hb_ValToStr( xVal ) + "(" + cType + ")"
   next

   DbgSend( cOut )

return nil

static function DbgSendStack()

   local i, cOut

   cOut := "STACK"
   for i := 2 to 20
      if Empty( ProcName( i ) ); exit; endif
      cOut += " " + ProcName( i ) + "(" + LTrim( Str( ProcLine( i ) ) ) + ")"
   next

   DbgSend( cOut )

return nil

static function DbgSend( cMsg )

   if s_lConnected .and. s_hSocket != nil
      hb_socketSend( s_hSocket, cMsg + Chr(10) )
   endif

return nil

static function DbgRecv()

   local cBuf := Space( 4096 ), nLen

   if ! s_lConnected .or. s_hSocket == nil
      return nil
   endif

   nLen := hb_socketRecv( s_hSocket, @cBuf )
   if nLen <= 0
      s_lConnected := .f.
      return nil
   endif

return AllTrim( Left( cBuf, nLen ) )
```

- [ ] **Step 2: Verify hbsocket.ch exists**

Run: `ls ~/harbour/include/hbsocket.ch`
Expected: file exists with HB_SOCKET_AF_INET and other constants.
If not found, define `#define HB_SOCKET_AF_INET 2` inline.

- [ ] **Step 3: Verify __dbgSetEntry is available in Harbour**

The `.hrb` hook function `hb_dbg_SetEntry` is C-level. At Harbour level we need `__dbgSetEntry()`. Check:
Run: `grep -r "__dbgSetEntry\|__DBGSETENTRY" ~/harbour/include/ ~/harbour/lib/`
If `__dbgSetEntry` is a Harbour function in libhbdebug (it should be — we saw `HB_FUN___DBGSETENTRY` in libhbdebug.a), we can call it. If the Harbour-level call doesn't work, use the C wrapper approach from cocoa_editor.mm.

- [ ] **Step 4: Commit**

```bash
git add harbour/dbgclient.prg
git commit -m "feat(debug): add dbgclient.prg socket debug client"
```

---

### Task 2: Add TCP server to the IDE (cocoa_editor.mm)

The IDE needs a TCP server that listens on port 19800, accepts one connection from the user's debug process, receives messages, and dispatches commands.

**Files:**
- Modify: `backends/cocoa/cocoa_editor.mm` (debug section, lines ~2579-3120)

- [ ] **Step 1: Add TCP server state variables**

Add after the existing debug state variables (around line 2606):

```c
/* Socket debug server */
static int             s_dbgServerFD = -1;    /* listening socket */
static int             s_dbgClientFD = -1;    /* connected client */
static NSFileHandle *  s_dbgClientHandle = nil;
static NSFileHandle *  s_dbgServerHandle = nil;
```

- [ ] **Step 2: Write DbgServerStart / DbgServerStop functions**

```c
/* Start TCP server on given port. Returns 0 on success, -1 on error. */
static int DbgServerStart( int port )
{
   int fd = socket( AF_INET, SOCK_STREAM, 0 );
   if( fd < 0 ) return -1;

   int yes = 1;
   setsockopt( fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes) );

   struct sockaddr_in addr;
   memset( &addr, 0, sizeof(addr) );
   addr.sin_family = AF_INET;
   addr.sin_addr.s_addr = htonl( INADDR_LOOPBACK );
   addr.sin_port = htons( (uint16_t)port );

   if( bind( fd, (struct sockaddr *)&addr, sizeof(addr) ) < 0 ||
       listen( fd, 1 ) < 0 )
   {
      close( fd );
      return -1;
   }

   s_dbgServerFD = fd;
   DbgOutput( "Debug server listening on port " );
   char portStr[16]; snprintf(portStr, sizeof(portStr), "%d\n", port);
   DbgOutput( portStr );
   return 0;
}

/* Accept one client connection (blocking with timeout). Returns 0 on success. */
static int DbgServerAccept( double timeoutSec )
{
   fd_set fds;
   FD_ZERO( &fds );
   FD_SET( s_dbgServerFD, &fds );
   struct timeval tv;
   tv.tv_sec = (long)timeoutSec;
   tv.tv_usec = (long)((timeoutSec - tv.tv_sec) * 1e6);

   /* Pump Cocoa events while waiting */
   while( select( s_dbgServerFD + 1, &fds, NULL, NULL, &tv ) == 0 )
   {
      @autoreleasepool {
         NSEvent * ev = [NSApp nextEventMatchingMask:NSEventMaskAny
            untilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]
            inMode:NSDefaultRunLoopMode dequeue:YES];
         if( ev ) [NSApp sendEvent:ev];
      }
      if( s_dbgState == DBG_STOPPED ) return -1;
      FD_ZERO( &fds );
      FD_SET( s_dbgServerFD, &fds );
      tv.tv_sec = 0; tv.tv_usec = 200000;  /* 200ms poll */
   }

   s_dbgClientFD = accept( s_dbgServerFD, NULL, NULL );
   if( s_dbgClientFD < 0 ) return -1;
   DbgOutput( "Debug client connected.\n" );
   return 0;
}

/* Send a command string to the debug client */
static void DbgServerSend( const char * cmd )
{
   if( s_dbgClientFD < 0 ) return;
   char buf[512];
   snprintf( buf, sizeof(buf), "%s\n", cmd );
   send( s_dbgClientFD, buf, strlen(buf), 0 );
}

/* Receive one line from the debug client (blocking with Cocoa event pump) */
static int DbgServerRecv( char * buf, int bufSize )
{
   if( s_dbgClientFD < 0 ) return -1;

   fd_set fds;
   struct timeval tv;

   while(1) {
      FD_ZERO( &fds );
      FD_SET( s_dbgClientFD, &fds );
      tv.tv_sec = 0; tv.tv_usec = 100000; /* 100ms */

      int r = select( s_dbgClientFD + 1, &fds, NULL, NULL, &tv );
      if( r > 0 ) {
         ssize_t n = recv( s_dbgClientFD, buf, (size_t)(bufSize - 1), 0 );
         if( n <= 0 ) return -1;
         buf[n] = 0;
         /* Strip trailing newline */
         while( n > 0 && (buf[n-1] == '\n' || buf[n-1] == '\r') ) buf[--n] = 0;
         return (int)n;
      }

      /* Pump Cocoa events while waiting */
      @autoreleasepool {
         NSEvent * ev = [NSApp nextEventMatchingMask:NSEventMaskAny
            untilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]
            inMode:NSDefaultRunLoopMode dequeue:YES];
         if( ev ) [NSApp sendEvent:ev];
      }

      if( s_dbgState == DBG_STOPPED ) return -1;
   }
}

/* Stop server and client */
static void DbgServerStop(void)
{
   if( s_dbgClientFD >= 0 ) { close( s_dbgClientFD ); s_dbgClientFD = -1; }
   if( s_dbgServerFD >= 0 ) { close( s_dbgServerFD ); s_dbgServerFD = -1; }
}
```

- [ ] **Step 3: Add includes**

At top of cocoa_editor.mm, add:
```c
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
```

- [ ] **Step 4: Commit**

```bash
git add backends/cocoa/cocoa_editor.mm
git commit -m "feat(debug): add TCP server for socket-based debugger"
```

---

### Task 3: Rewrite IDE_DebugStart to use socket protocol

Replace the old .hrb-based `IDE_DebugStart` with a new flow: start server, compile native executable with dbgclient.prg, launch process, accept connection, enter command loop.

**Files:**
- Modify: `backends/cocoa/cocoa_editor.mm` (replace IDE_DebugStart)

- [ ] **Step 1: Replace IDE_DebugStart**

Replace the existing `HB_FUNC( IDE_DEBUGSTART )` with:

```c
/* IDE_DebugStart2( cBuildDir ) — start socket debug session
 * 1. Start TCP server on port 19800
 * 2. Launch user executable (already compiled by TBDebugRun)
 * 3. Accept connection
 * 4. Enter command loop: receive PAUSE, dispatch to Harbour callback, send commands
 */
HB_FUNC( IDE_DEBUGSTART2 )
{
   const char * cExePath = hb_parc(1);
   PHB_ITEM pOnPause = hb_param(2, HB_IT_BLOCK);

   if( !cExePath || s_dbgState != DBG_IDLE ) { hb_retl( HB_FALSE ); return; }

   if( s_dbgOnPause ) { hb_itemRelease( s_dbgOnPause ); s_dbgOnPause = NULL; }
   if( pOnPause ) s_dbgOnPause = hb_itemNew( pOnPause );

   /* Step 1: Start TCP server */
   if( DbgServerStart( 19800 ) != 0 )
   {
      DbgOutput( "ERROR: Could not start debug server on port 19800\n" );
      hb_retl( HB_FALSE );
      return;
   }

   s_dbgState = DBG_STEPPING;
   s_nBreakpoints = 0;
   DbgOutput( "=== Debug session started (socket mode) ===\n" );

   /* Step 2: Launch user executable in background */
   {
      char cmd[1024];
      snprintf( cmd, sizeof(cmd), "\"%s\" &", cExePath );
      system( cmd );
   }

   DbgOutput( "Waiting for debug client to connect...\n" );

   /* Step 3: Accept connection (with timeout / UI pump) */
   if( DbgServerAccept( 30.0 ) != 0 )
   {
      DbgOutput( "ERROR: Debug client did not connect within 30 seconds\n" );
      DbgServerStop();
      s_dbgState = DBG_IDLE;
      hb_retl( HB_FALSE );
      return;
   }

   /* Step 4: Command loop — receive messages, dispatch to UI */
   char recvBuf[4096];
   while( s_dbgState != DBG_IDLE && s_dbgState != DBG_STOPPED )
   {
      int n = DbgServerRecv( recvBuf, sizeof(recvBuf) );
      if( n <= 0 ) {
         DbgOutput( "Debug client disconnected.\n" );
         break;
      }

      if( strncmp( recvBuf, "PAUSE ", 6 ) == 0 )
      {
         /* Parse module:line */
         char * colon = strchr( recvBuf + 6, ':' );
         if( colon ) {
            *colon = 0;
            const char * module = recvBuf + 6;
            int line = atoi( colon + 1 );

            strncpy( s_dbgModule, module, sizeof(s_dbgModule) - 1 );
            s_dbgLine = line;

            /* Call Harbour callback */
            if( s_dbgOnPause && HB_IS_BLOCK( s_dbgOnPause ) )
            {
               PHB_ITEM pMod  = hb_itemPutC( NULL, module );
               PHB_ITEM pLine = hb_itemPutNI( NULL, line );
               hb_itemDo( s_dbgOnPause, 2, pMod, pLine );
               hb_itemRelease( pMod );
               hb_itemRelease( pLine );
            }

            /* Request locals and stack */
            DbgServerSend( "GETLOCALS" );
            n = DbgServerRecv( recvBuf, sizeof(recvBuf) );
            if( n > 0 && strncmp( recvBuf, "LOCALS", 6 ) == 0 )
            {
               /* Parse and update locals table */
               /* Format: LOCALS name=val(T) name2=val2(T) */
               DbgOutput( recvBuf );
               DbgOutput( "\n" );
            }

            DbgServerSend( "GETSTACK" );
            n = DbgServerRecv( recvBuf, sizeof(recvBuf) );
            if( n > 0 && strncmp( recvBuf, "STACK", 5 ) == 0 )
            {
               DbgOutput( recvBuf );
               DbgOutput( "\n" );
            }

            /* Wait for user action (Step/Go/Stop) via UI buttons */
            while( s_dbgState == DBG_PAUSED )
            {
               @autoreleasepool {
                  NSEvent * ev = [NSApp nextEventMatchingMask:NSEventMaskAny
                     untilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]
                     inMode:NSDefaultRunLoopMode dequeue:YES];
                  if( ev ) [NSApp sendEvent:ev];
               }
            }

            /* Send command based on new state */
            if( s_dbgState == DBG_STEPPING )
               DbgServerSend( "STEP" );
            else if( s_dbgState == DBG_STEPOVER )
               DbgServerSend( "STEP" );  /* simplified: same as step for now */
            else if( s_dbgState == DBG_RUNNING )
               DbgServerSend( "GO" );
            else if( s_dbgState == DBG_STOPPED )
               DbgServerSend( "QUIT" );

            /* Reset to stepping for next PAUSE */
            if( s_dbgState == DBG_STEPPING || s_dbgState == DBG_STEPOVER )
               s_dbgState = DBG_PAUSED;
         }
      }
      else if( strncmp( recvBuf, "HELLO", 5 ) == 0 )
      {
         DbgOutput( "Client: " );
         DbgOutput( recvBuf );
         DbgOutput( "\n" );
         s_dbgState = DBG_PAUSED;  /* pause on first line */
      }
   }

   /* Cleanup */
   DbgServerSend( "QUIT" );
   DbgServerStop();
   s_dbgState = DBG_IDLE;
   DbgOutput( "=== Debug session ended ===\n" );

   if( s_dbgStatusLbl )
      [s_dbgStatusLbl setStringValue:@"Ready"];

   hb_retl( HB_TRUE );
}
```

- [ ] **Step 2: Commit**

```bash
git add backends/cocoa/cocoa_editor.mm
git commit -m "feat(debug): rewrite IDE_DebugStart2 with socket command loop"
```

---

### Task 4: Modify TBDebugRun to compile native + inject dbgclient.prg

Change `TBDebugRun()` to compile the user's project as a native executable (like `TBRun`) but including `dbgclient.prg`, and call `IDE_DebugStart2` instead of the old `IDE_DebugStart`.

**Files:**
- Modify: `samples/hbbuilder_macos.prg` (TBDebugRun function)

- [ ] **Step 1: Rewrite TBDebugRun**

Replace the body of `TBDebugRun()` (lines ~1669-1759) with a flow that:
1. Saves project files (same as TBRun)
2. Assembles `debug_main.prg` = user code + `dbgclient.prg` + startup wrapper
3. Compiles with Harbour to C (`-b` flag for debug info)
4. Compiles C to object with clang
5. Links native executable with Harbour libs + frameworks
6. Opens debug panel
7. Calls `IDE_DebugStart2( cExePath, {|m,l| OnDebugPause(m,l)} )`

The key difference from TBRun: the generated `Project1.prg` wrapper calls `DbgClientStart(19800)` before `oApp:Run()`.

```harbour
static function TBDebugRun()

   local cBuildDir, cOutput, cLog, i, lError
   local cHbDir, cHbBin, cHbInc, cHbLib, cProjDir
   local cAllPrg, cCmd, cMainPrg

   SaveActiveFormCode()

   cBuildDir := "/tmp/hbbuilder_debug"
   cHbDir   := GetEnv( "HOME" ) + "/harbour"
   cHbInc   := cHbDir + "/include"
   cProjDir := HB_DirBase() + ".."
   cLog     := ""
   lError   := .F.

   if File( cHbDir + "/bin/darwin/clang/harbour" )
      cHbBin := cHbDir + "/bin/darwin/clang"
      cHbLib := cHbDir + "/lib/darwin/clang"
   else
      cHbBin := cHbDir + "/bin"
      cHbLib := cHbDir + "/lib"
   endif

   MAC_ShellExec( "mkdir -p " + cBuildDir )

   // Step 1: Save user code
   cLog += "[1] Saving project files..." + Chr(10)
   for i := 1 to Len( aForms )
      MemoWrit( cBuildDir + "/" + aForms[i][1] + ".prg", ;
         CodeEditorGetTabText( hCodeEditor, i + 1 ) )
   next

   // Copy framework
   if File( HB_DirBase() + "../Resources/classes.prg" )
      MAC_ShellExec( "cp " + HB_DirBase() + "../Resources/classes.prg " + cBuildDir + "/" )
      MAC_ShellExec( "cp " + HB_DirBase() + "../Resources/hbbuilder.ch " + cBuildDir + "/" )
   else
      MAC_ShellExec( "cp " + cProjDir + "/harbour/classes.prg " + cBuildDir + "/" )
      MAC_ShellExec( "cp " + cProjDir + "/harbour/hbbuilder.ch " + cBuildDir + "/" )
   endif

   // Copy dbgclient.prg
   if File( HB_DirBase() + "../Resources/dbgclient.prg" )
      MAC_ShellExec( "cp " + HB_DirBase() + "../Resources/dbgclient.prg " + cBuildDir + "/" )
   else
      MAC_ShellExec( "cp " + cProjDir + "/harbour/dbgclient.prg " + cBuildDir + "/" )
   endif

   // Step 2: Build debug_main.prg
   cLog += "[2] Assembling debug_main.prg..." + Chr(10)
   cAllPrg := '#include "hbbuilder.ch"' + Chr(10) + Chr(10)

   // User Project1.prg — inject DbgClientStart() call before oApp:Run()
   cMainPrg := CodeEditorGetTabText( hCodeEditor, 1 )
   cMainPrg := StrTran( cMainPrg, '#include "hbbuilder.ch"', "" )
   // Inject debug client start before oApp:Run()
   cMainPrg := StrTran( cMainPrg, "oApp:Run()", ;
      "DbgClientStart( 19800 )" + Chr(10) + "   oApp:Run()" )
   cAllPrg += cMainPrg + Chr(10)

   // Form code
   for i := 1 to Len( aForms )
      cAllPrg += MemoRead( cBuildDir + "/" + aForms[i][1] + ".prg" ) + Chr(10)
   next

   // Framework + debug client
   cAllPrg += MemoRead( cBuildDir + "/classes.prg" ) + Chr(10)
   cAllPrg += MemoRead( cBuildDir + "/dbgclient.prg" ) + Chr(10)
   MemoWrit( cBuildDir + "/debug_main.prg", cAllPrg )

   // Step 3: Compile Harbour → C
   cLog += "[3] Compiling (harbour -b -n -w)..." + Chr(10)
   cCmd := cHbBin + "/harbour " + cBuildDir + "/debug_main.prg -b -n -w -q" + ;
           " -I" + cHbInc + " -I" + cBuildDir + ;
           " -o" + cBuildDir + "/debug_main.c 2>&1"
   cOutput := MAC_ShellExec( cCmd )
   if "Error" $ cOutput
      cLog += cOutput + Chr(10)
      lError := .t.
   else
      cLog += "    OK" + Chr(10)
   endif

   // Step 4: Compile C → object
   if ! lError
      cLog += "[4] Compiling C..." + Chr(10)
      cCmd := "clang -c -O0 -g " + cBuildDir + "/debug_main.c" + ;
              " -I" + cHbInc + " -o " + cBuildDir + "/debug_main.o 2>&1"
      cOutput := MAC_ShellExec( cCmd )
      if "error:" $ Lower( cOutput )
         cLog += cOutput + Chr(10)
         lError := .t.
      else
         cLog += "    OK" + Chr(10)
      endif
   endif

   // Step 5: Link
   if ! lError
      cLog += "[5] Linking..." + Chr(10)
      cCmd := "clang " + cBuildDir + "/debug_main.o" + ;
              " -L" + cHbLib + ;
              " -lhbvm -lhbrtl -lhbcommon -lhbcpage -lhblang" + ;
              " -lhbmacro -lhbpp -lhbrdd -lhbcplr -lhbdebug" + ;
              " -lhbct -lhbextern -lhbsqlit3" + ;
              " -lrddntx -lrddnsx -lrddcdx -lrddfpt" + ;
              " -lhbhsx -lhbsix -lhbusrrdd" + ;
              " -lgtcgi -lgtstd" + ;
              " -framework Cocoa" + ;
              " -lm -lpthread -lsqlite3" + ;
              " -o " + cBuildDir + "/DebugApp 2>&1"
      cOutput := MAC_ShellExec( cCmd )
      if "error:" $ Lower( cOutput )
         cLog += cOutput + Chr(10)
         lError := .t.
      else
         cLog += "    OK" + Chr(10)
      endif
   endif

   if lError
      MAC_BuildErrorDialog( "Debug Build Failed", cLog )
      return nil
   endif

   if ! File( cBuildDir + "/DebugApp" )
      cLog += "ERROR: DebugApp was not created" + Chr(10)
      MAC_BuildErrorDialog( "Debug Build Failed", cLog )
      return nil
   endif

   // Step 6: Launch debug session
   MAC_DebugPanel()
   MAC_DebugSetStatus( "Building... done. Starting debug session." )

   IDE_DebugStart2( cBuildDir + "/DebugApp", ;
      { |cModule, nLine| OnDebugPause( cModule, nLine ) } )

return nil
```

- [ ] **Step 2: Copy dbgclient.prg into the .app bundle during build**

In `build_mac.sh`, add a copy step in the bundle creation section:
```bash
cp "$PROJDIR/harbour/dbgclient.prg" "$BUNDLE/Contents/Resources/dbgclient.prg"
```

- [ ] **Step 3: Commit**

```bash
git add samples/hbbuilder_macos.prg samples/build_mac.sh
git commit -m "feat(debug): TBDebugRun compiles native exe with socket debug client"
```

---

### Task 5: Wire up the debug panel buttons to the socket protocol

The existing debug panel toolbar buttons (Step, Over, Go, Stop) change `s_dbgState`, which the command loop in `IDE_DebugStart2` reads to send commands. The buttons already work via `HBDebugTarget`. Verify they function with the new flow and fix `OnDebugPause` to work with socket data instead of in-process debug API.

**Files:**
- Modify: `samples/hbbuilder_macos.prg` (OnDebugPause, DebugStepInto, DebugStepOver)

- [ ] **Step 1: Simplify OnDebugPause**

The socket version receives locals/stack from the TCP stream, not from in-process API. The `OnDebugPause` callback just updates the status — locals and stack are handled by the C command loop.

```harbour
static function OnDebugPause( cModule, nLine )
   MAC_DebugSetStatus( "Paused at " + cModule + ":" + LTrim(Str(nLine)) )
return nil
```

- [ ] **Step 2: Update DebugStepInto / DebugStepOver**

These already work — they set `s_dbgState` which the C loop reads. No change needed, but remove the state check since the loop handles it:

```harbour
static function DebugStepOver()
   IDE_DebugStep()  // sets state to DBG_STEPPING
return nil

static function DebugStepInto()
   IDE_DebugStep()  // sets state to DBG_STEPPING
return nil
```

- [ ] **Step 3: Commit**

```bash
git add samples/hbbuilder_macos.prg
git commit -m "feat(debug): simplify debug callbacks for socket protocol"
```

---

### Task 6: Clean up old .hrb debug code and remove traces

Remove the old `IDE_DebugStart` (hrb-based), remove fprintf debug traces, clean up unused code.

**Files:**
- Modify: `backends/cocoa/cocoa_editor.mm`
- Modify: `samples/hbbuilder_macos.prg`

- [ ] **Step 1: Remove old IDE_DebugStart**

Delete or comment out the old `HB_FUNC( IDE_DEBUGSTART )` that uses HB_HRBRUN.

- [ ] **Step 2: Remove all fprintf debug traces**

Search for `fprintf.*DBG:` and `fprintf.*HOOK:` and remove them.

- [ ] **Step 3: Remove REQUEST HB_HRBRUN**

No longer needed since we don't use .hrb.

- [ ] **Step 4: Remove IsDebugMode / IDE_IsDebugMode**

No longer needed — the user's app runs as a separate process, so `TApplication:Run()` always calls `Activate()` normally. The debug client handles pausing via the socket, not by skipping `[NSApp run]`.

- [ ] **Step 5: Commit**

```bash
git add backends/cocoa/cocoa_editor.mm samples/hbbuilder_macos.prg harbour/classes.prg
git commit -m "refactor(debug): remove old .hrb debugger, cleanup traces"
```

---

### Task 7: Build, test, update todo.md

**Files:**
- Modify: `todo.md`
- Modify: `ChangeLog.txt`

- [ ] **Step 1: Build and test**

```bash
cd samples && ./build_mac.sh
cp HbBuilder ../bin/HbBuilder
cp HbBuilder ../bin/HbBuilder.app/Contents/MacOS/HbBuilder
```

- [ ] **Step 2: Test debug flow**

1. Run HbBuilder
2. Create a simple form with a button
3. Click Debug button
4. Verify: compile succeeds, debug panel shows, client connects
5. Click Step — verify source position advances
6. Click Go — verify app runs freely
7. Click Stop — verify session ends cleanly

- [ ] **Step 3: Update todo.md**

Add entry documenting the socket debugger implementation.

- [ ] **Step 4: Update ChangeLog.txt**

Add session entry for socket debugger.

- [ ] **Step 5: Commit and push**

```bash
git add -A
git commit -m "feat(debug): socket-based debugger with TCP protocol"
git push
```
