/*
 * cocoa_inspector_reg.c - Harbour module registration for cocoa_inspector functions
 *
 * This module registers the HB_FUNC functions defined in cocoa_inspector.m
 * so they can be found by hb_dynsymFind().
 */

#include "hbapi.h"
#include "hbinit.h"

/* Declare the functions from cocoa_inspector.m */
HB_FUNC_EXTERN( INS_CREATE );
HB_FUNC_EXTERN( INS_REFRESHWITHDATA );
HB_FUNC_EXTERN( INS_BRINGTOFRONT );
HB_FUNC_EXTERN( INS_DESTROY );
HB_FUNC_EXTERN( _INSGETDATA );
HB_FUNC_EXTERN( _INSSETDATA );
HB_FUNC_EXTERN( INS_SETDEBUGMODE );
HB_FUNC_EXTERN( INS_SETDEBUGLOCALS );
HB_FUNC_EXTERN( INS_SETDEBUGSTACK );

/* Module initialization */
HB_INIT_SYMBOLS_BEGIN( hb_vm_SymbolInit_COCOA_INSPECTOR )
   { "INS_CREATE",           {HB_FS_PUBLIC}, {HB_FUNCNAME( INS_CREATE )}, NULL },
   { "INS_REFRESHWITHDATA",  {HB_FS_PUBLIC}, {HB_FUNCNAME( INS_REFRESHWITHDATA )}, NULL },
   { "INS_BRINGTOFRONT",     {HB_FS_PUBLIC}, {HB_FUNCNAME( INS_BRINGTOFRONT )}, NULL },
   { "INS_DESTROY",          {HB_FS_PUBLIC}, {HB_FUNCNAME( INS_DESTROY )}, NULL },
   { "_INSGETDATA",          {HB_FS_PUBLIC}, {HB_FUNCNAME( _INSGETDATA )}, NULL },
   { "_INSSETDATA",          {HB_FS_PUBLIC}, {HB_FUNCNAME( _INSSETDATA )}, NULL },
   { "INS_SETDEBUGMODE",     {HB_FS_PUBLIC}, {HB_FUNCNAME( INS_SETDEBUGMODE )}, NULL },
   { "INS_SETDEBUGLOCALS",   {HB_FS_PUBLIC}, {HB_FUNCNAME( INS_SETDEBUGLOCALS )}, NULL },
   { "INS_SETDEBUGSTACK",    {HB_FS_PUBLIC}, {HB_FUNCNAME( INS_SETDEBUGSTACK )}, NULL },
HB_INIT_SYMBOLS_END( hb_vm_SymbolInit_COCOA_INSPECTOR )

/* Module entry point */
HB_CALL_ON_STARTUP_BEGIN( _hb_cocoa_inspector_init_ )
   hb_vm_SymbolInit_COCOA_INSPECTOR();
HB_CALL_ON_STARTUP_END( _hb_cocoa_inspector_init_ )

#if defined( HB_PRAGMA_STARTUP )
   #pragma startup _hb_cocoa_inspector_init_
#elif defined( HB_DATASEG_STARTUP )
   #define HB_DATASEG_BODY    HB_DATASEG_FUNC( _hb_cocoa_inspector_init_ )
   #include "hbiniseg.h"
#endif