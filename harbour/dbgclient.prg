// dbgclient.prg — Socket-based debug client for HbBuilder
//
// When concatenated into debug_main.prg, module-level STATIC declarations
// would cause E0004 ("STATIC follows executable"). To avoid this, all state
// is stored in a persistent array returned by DbgState().

#include "hbsocket.ch"

#define DBG_SOCKET    1
#define DBG_CONNECTED 2
#define DBG_MODULE    3
#define DBG_READY     4

static function DbgState()
   static s_aState := nil
   if s_aState == nil
      s_aState := { nil, .f., "", .f. }  // socket, connected, module, ready
   endif
return s_aState

function DbgClientStart( nPort )

   local hSocket, aAddr, aS, cReply

   if nPort == nil; nPort := 19800; endif

   hSocket := hb_socketOpen( HB_SOCKET_AF_INET, 1 /* SOCK_STREAM */, 0 )
   if Empty( hSocket )
      OutErr( "DBG CLIENT: socket open failed" + Chr(10) )
      return .f.
   endif

   aAddr := { HB_SOCKET_AF_INET, "127.0.0.1", nPort }
   if ! hb_socketConnect( hSocket, aAddr )
      OutErr( "DBG CLIENT: connect failed" + Chr(10) )
      hb_socketClose( hSocket )
      return .f.
   endif

   aS := DbgState()
   aS[ DBG_SOCKET ] := hSocket
   aS[ DBG_CONNECTED ] := .t.

   OutErr( "DBG CLIENT: connected on port " + LTrim(Str(nPort)) + Chr(10) )

   OutErr( "DBG-CLI: installing C hook via DbgHookInstall" + Chr(10) )

   // Install C-level debug hook (dbghook.c) that forwards to our Harbour function
   DbgHookInstall( { |nMode, nLine, cName| ;
      DbgHook( nMode, nLine, cName, nil, nil ) } )

   OutErr( "DBG-CLI: sending HELLO" + Chr(10) )
   // Send hello
   DbgSend( "HELLO " + ProcFile(2) )

   // Wait for first STEP command from IDE before continuing
   OutErr( "DBG-CLI: waiting for initial STEP..." + Chr(10) )
   cReply := DbgRecv()
   OutErr( "DBG-CLI: got reply='" + If( cReply != nil, cReply, "(nil)" ) + "'" + Chr(10) )

   // Now enable the hook — from this point, every Harbour line will trigger PAUSE
   aS := DbgState()
   aS[ DBG_READY ] := .t.
   OutErr( "DBG-CLI: hook READY" + Chr(10) )

return .t.

static function DbgHook( nMode, nLine, cName, nIndex, xFrame )

   local cCmd, aS := DbgState()

   HB_SYMBOL_UNUSED( nIndex )
   HB_SYMBOL_UNUSED( xFrame )

   if ! aS[ DBG_CONNECTED ] .or. ! aS[ DBG_READY ]
      return nil
   endif

   if nMode == 1 .and. cName != nil
      aS[ DBG_MODULE ] := cName
      OutErr( "DBG-CLI: module=" + cName + Chr(10) )
      return nil
   endif

   if nMode != 5
      return nil
   endif

   OutErr( "DBG-CLI: PAUSE " + aS[ DBG_MODULE ] + ":" + LTrim( Str( nLine ) ) + Chr(10) )
   DbgSend( "PAUSE " + aS[ DBG_MODULE ] + ":" + LTrim( Str( nLine ) ) )

   do while aS[ DBG_CONNECTED ]
      cCmd := DbgRecv()
      OutErr( "DBG-CLI: recv='" + If( cCmd != nil, cCmd, "(nil)" ) + "'" + Chr(10) )
      if cCmd == nil
         aS[ DBG_CONNECTED ] := .f.
         return nil
      endif

      if Left( cCmd, 4 ) == "QUIT"
         aS[ DBG_CONNECTED ] := .f.
         hb_socketClose( aS[ DBG_SOCKET ] )
         QUIT
         return nil
      endif

      if Left( cCmd, 4 ) == "STEP" .or. Left( cCmd, 2 ) == "GO"
         exit
      endif

      if Left( cCmd, 9 ) == "GETLOCALS"
         DbgSendLocals()
      elseif Left( cCmd, 8 ) == "GETSTACK"
         DbgSendStack()
      endif
   enddo

return nil

static function DbgSendLocals()

   local aLocals, i, cOut, cName, xVal, cType

   cOut := "LOCALS"
   BEGIN SEQUENCE
      aLocals := __dbgVmLocalList( 4 )  // skip DbgSendLocals+DbgHook+C_hook+caller
      if ValType( aLocals ) == "A"
         for i := 1 to Len( aLocals )
            cName := aLocals[i]
            if ValType( cName ) != "C"; loop; endif
            BEGIN SEQUENCE
               xVal := __dbgVmVarLGet( 4, i )
            RECOVER
               xVal := "(error)"
            END SEQUENCE
            cType := ValType( xVal )
            cOut += " " + cName + "=" + hb_ValToStr( xVal ) + "(" + cType + ")"
         next
      endif
   END SEQUENCE

   DbgSend( cOut )

return nil

static function DbgSendStack()

   local i, cOut

   cOut := "STACK"
   for i := 3 to 25
      if Empty( ProcName( i ) ); exit; endif
      cOut += " " + ProcName( i ) + "(" + LTrim( Str( ProcLine( i ) ) ) + ")"
   next

   DbgSend( cOut )

return nil

static function DbgSend( cMsg )

   local aS := DbgState()
   if aS[ DBG_CONNECTED ] .and. aS[ DBG_SOCKET ] != nil
      hb_socketSend( aS[ DBG_SOCKET ], cMsg + Chr(10) )
   endif

return nil

static function DbgRecv()

   local cBuf := Space( 4096 ), nLen, aS := DbgState()

   if ! aS[ DBG_CONNECTED ] .or. aS[ DBG_SOCKET ] == nil
      return nil
   endif

   nLen := hb_socketRecv( aS[ DBG_SOCKET ], @cBuf )
   if nLen <= 0
      aS[ DBG_CONNECTED ] := .f.
      return nil
   endif

   cBuf := Left( cBuf, nLen )
   do while Right( cBuf, 1 ) == Chr(10) .or. Right( cBuf, 1 ) == Chr(13)
      cBuf := Left( cBuf, Len( cBuf ) - 1 )
   enddo

return cBuf
