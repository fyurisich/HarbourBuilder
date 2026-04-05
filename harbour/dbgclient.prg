// dbgclient.prg — Socket-based debug client for HbBuilder
//
// When concatenated into debug_main.prg, module-level STATIC declarations
// would cause E0004 ("STATIC follows executable"). To avoid this, all state
// is stored in a persistent array returned by DbgState().

#include "hbsocket.ch"

#define DBG_SOCKET    1
#define DBG_CONNECTED 2
#define DBG_MODULE    3

static function DbgState()
   static s_aState := nil
   if s_aState == nil
      s_aState := { nil, .f., "" }  // socket, connected, module
   endif
return s_aState

function DbgClientStart( nPort )

   local hSocket, aAddr, aS

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

   // Install debug hook
   __dbgSetEntry( { |nMode, nLine, cName, nIndex, xFrame| ;
      DbgHook( nMode, nLine, cName, nIndex, xFrame ) } )

   // Send hello
   DbgSend( "HELLO " + ProcFile(2) )

return .t.

static function DbgHook( nMode, nLine, cName, nIndex, xFrame )

   local cCmd, aS := DbgState()

   HB_SYMBOL_UNUSED( nIndex )
   HB_SYMBOL_UNUSED( xFrame )

   if ! aS[ DBG_CONNECTED ]
      return nil
   endif

   if nMode == 1 .and. cName != nil
      aS[ DBG_MODULE ] := cName
      return nil
   endif

   if nMode != 5
      return nil
   endif

   DbgSend( "PAUSE " + aS[ DBG_MODULE ] + ":" + LTrim( Str( nLine ) ) )

   do while aS[ DBG_CONNECTED ]
      cCmd := DbgRecv()
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
   aLocals := __dbgVmLocalList( 3 )  // level 3 = caller's caller (skip hook+wrapper)
   if ValType( aLocals ) == "A"
      for i := 1 to Len( aLocals )
         cName := aLocals[i]
         xVal  := __dbgVmVarLGet( 3, i )
         cType := ValType( xVal )
         cOut += " " + cName + "=" + hb_ValToStr( xVal ) + "(" + cType + ")"
      next
   endif

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
