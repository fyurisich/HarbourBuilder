/* Standard dialog runtime backends for HbBuilder projects (Windows).
 * Exposes W32_ExecOpenDialog / W32_ExecSaveDialog / W32_ExecFontDialog /
 * W32_ExecColorDialog used by TOpenDialog/TSaveDialog/TFontDialog/
 * TColorDialog classes in classes.prg.
 */
#include <windows.h>
#include <commdlg.h>
#include <string.h>
#include <hbapi.h>
#include <hbapiitm.h>

/* Convert Delphi-style filter "Text (*.txt)|*.txt|All|*.*" to Win32 double-NUL */
static void _dlgFilter( const char * src, char * dst, int dstSize )
{
   int di = 0;
   if( !src || !src[0] ) {
      lstrcpynA( dst, "All Files (*.*)", dstSize - 2 );
      di = (int) strlen( dst ) + 1;
      lstrcpynA( dst + di, "*.*", dstSize - di - 2 );
      di += (int) strlen( dst + di ) + 1;
      dst[di] = 0;
      return;
   }
   while( *src && di < dstSize - 2 ) {
      if( *src == '|' ) { dst[di++] = 0; src++; }
      else dst[di++] = *src++;
   }
   dst[di++] = 0;
   dst[di] = 0;
}

HB_FUNC( W32_EXECOPENDIALOG )
{
   OPENFILENAMEA ofn;
   char szFile[MAX_PATH] = "";
   char szFilter[1024];
   const char * cInit = hb_parc(3);
   const char * cExt  = hb_parc(4);

   _dlgFilter( hb_parc(2), szFilter, sizeof(szFilter) );

   memset( &ofn, 0, sizeof(ofn) );
   ofn.lStructSize     = sizeof(ofn);
   ofn.hwndOwner       = GetActiveWindow();
   ofn.lpstrFilter     = szFilter;
   ofn.lpstrFile       = szFile;
   ofn.nMaxFile        = MAX_PATH;
   ofn.lpstrTitle      = hb_parclen(1) ? hb_parc(1) : NULL;
   ofn.lpstrInitialDir = ( cInit && cInit[0] ) ? cInit : NULL;
   ofn.lpstrDefExt     = ( cExt && cExt[0] )   ? cExt  : NULL;
   ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_HIDEREADONLY;

   hb_retc( GetOpenFileNameA( &ofn ) ? szFile : "" );
}

HB_FUNC( W32_EXECSAVEDIALOG )
{
   OPENFILENAMEA ofn;
   char szFile[MAX_PATH] = "";
   char szFilter[1024];
   const char * cInit = hb_parc(3);
   const char * cExt  = hb_parc(4);
   const char * cName = hb_parc(5);

   _dlgFilter( hb_parc(2), szFilter, sizeof(szFilter) );
   if( cName && cName[0] ) lstrcpynA( szFile, cName, MAX_PATH );

   memset( &ofn, 0, sizeof(ofn) );
   ofn.lStructSize     = sizeof(ofn);
   ofn.hwndOwner       = GetActiveWindow();
   ofn.lpstrFilter     = szFilter;
   ofn.lpstrFile       = szFile;
   ofn.nMaxFile        = MAX_PATH;
   ofn.lpstrTitle      = hb_parclen(1) ? hb_parc(1) : NULL;
   ofn.lpstrInitialDir = ( cInit && cInit[0] ) ? cInit : NULL;
   ofn.lpstrDefExt     = ( cExt && cExt[0] )   ? cExt  : NULL;
   ofn.Flags = OFN_OVERWRITEPROMPT | OFN_HIDEREADONLY;

   hb_retc( GetSaveFileNameA( &ofn ) ? szFile : "" );
}

HB_FUNC( W32_EXECFONTDIALOG )
{
   CHOOSEFONTA cf;
   LOGFONTA lf;
   const char * cName = hb_parc(1);
   int nSize  = hb_parni(2);
   int nColor = hb_parni(3);
   int nStyle = hb_parni(4);
   HDC hdc;

   memset( &lf, 0, sizeof(lf) );
   if( cName && cName[0] ) lstrcpynA( lf.lfFaceName, cName, LF_FACESIZE );
   else                    lstrcpyA ( lf.lfFaceName, "Segoe UI" );

   hdc = GetDC( NULL );
   lf.lfHeight = -MulDiv( nSize > 0 ? nSize : 10, GetDeviceCaps( hdc, LOGPIXELSY ), 72 );
   ReleaseDC( NULL, hdc );
   lf.lfWeight    = ( nStyle & 1 ) ? FW_BOLD : FW_NORMAL;
   lf.lfItalic    = ( nStyle & 2 ) ? 1 : 0;
   lf.lfUnderline = ( nStyle & 4 ) ? 1 : 0;
   lf.lfCharSet   = DEFAULT_CHARSET;

   memset( &cf, 0, sizeof(cf) );
   cf.lStructSize = sizeof(cf);
   cf.hwndOwner   = GetActiveWindow();
   cf.lpLogFont   = &lf;
   cf.rgbColors   = nColor;
   cf.Flags       = CF_SCREENFONTS | CF_INITTOLOGFONTSTRUCT | CF_EFFECTS;

   if( ChooseFontA( &cf ) ) {
      PHB_ITEM aRet;
      int outStyle = 0;
      int pts;
      hdc = GetDC( NULL );
      pts = MulDiv( -lf.lfHeight, 72, GetDeviceCaps( hdc, LOGPIXELSY ) );
      ReleaseDC( NULL, hdc );
      if( lf.lfWeight >= FW_BOLD ) outStyle |= 1;
      if( lf.lfItalic )            outStyle |= 2;
      if( lf.lfUnderline )         outStyle |= 4;
      aRet = hb_itemArrayNew( 4 );
      hb_arraySetC ( aRet, 1, lf.lfFaceName );
      hb_arraySetNI( aRet, 2, pts );
      hb_arraySetNI( aRet, 3, (int) cf.rgbColors );
      hb_arraySetNI( aRet, 4, outStyle );
      hb_itemReturnRelease( aRet );
   } else {
      hb_ret();  /* NIL */
   }
}

HB_FUNC( W32_EXECCOLORDIALOG )
{
   CHOOSECOLORA cc;
   static COLORREF custColors[16] = {0};
   memset( &cc, 0, sizeof(cc) );
   cc.lStructSize  = sizeof(cc);
   cc.hwndOwner    = GetActiveWindow();
   cc.rgbResult    = (COLORREF) hb_parni(1);
   cc.lpCustColors = custColors;
   cc.Flags        = CC_RGBINIT | CC_FULLOPEN;

   hb_retni( ChooseColorA( &cc ) ? (int) cc.rgbResult : -1 );
}
