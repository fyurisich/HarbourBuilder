/* dbghook.c — C-level debug hook for socket debugger
 * Registers a C callback with hb_dbg_SetEntry() that forwards
 * debug events to a Harbour block (stored in a static). */

#include "hbapi.h"
#include "hbapiitm.h"
#include "hbvm.h"
#include "hbapidbg.h"

static PHB_ITEM s_pDbgBlock = NULL;
static int s_nReentrancy = 0;

static void DbgHookC( int nMode, int nLine, const char * szName,
                       int nIndex, PHB_ITEM pFrame )
{
   (void)nIndex; (void)pFrame;

   /* Prevent re-entrancy: the block callback executes Harbour pcode
    * which would trigger this hook again → infinite recursion */
   if( s_nReentrancy > 0 ) return;

   if( s_pDbgBlock && HB_IS_BLOCK( s_pDbgBlock ) )
   {
      s_nReentrancy++;
      PHB_ITEM pMode = hb_itemPutNI( NULL, nMode );
      PHB_ITEM pLine = hb_itemPutNI( NULL, nLine );
      PHB_ITEM pName = hb_itemPutC( NULL, szName ? szName : "" );

      hb_itemDo( s_pDbgBlock, 3, pMode, pLine, pName );

      hb_itemRelease( pMode );
      hb_itemRelease( pLine );
      hb_itemRelease( pName );

      s_nReentrancy--;
   }
}

/* DbgHookInstall( bBlock ) — install C-level debug hook that calls bBlock
 * bBlock receives: nMode, nLine, cName */
HB_FUNC( DBGHOOKINSTALL )
{
   PHB_ITEM pBlock = hb_param( 1, HB_IT_BLOCK );
   if( pBlock )
   {
      if( s_pDbgBlock )
         hb_itemRelease( s_pDbgBlock );
      s_pDbgBlock = hb_itemNew( pBlock );
      hb_dbg_SetEntry( DbgHookC );
   }
}

/* DbgHookRemove() — remove the debug hook */
HB_FUNC( DBGHOOKREMOVE )
{
   hb_dbg_SetEntry( NULL );
   if( s_pDbgBlock )
   {
      hb_itemRelease( s_pDbgBlock );
      s_pDbgBlock = NULL;
   }
}
