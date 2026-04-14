/* Project1.prg - iOS Sample Project */

#include "hbclass.ch"

PROCEDURE Main()

   LOCAL oApp

   oApp := iOSApp():New()
   oApp:Run()

RETURN

/* ------------------------------------------------------------------- */

CLASS iOSApp

   DATA hForm
   DATA hLabel
   DATA hButton
   DATA hEdit
   DATA nClicks INIT 0

   METHOD New()
   METHOD Run()

ENDCLASS

METHOD New() CLASS iOSApp

   ::hForm := UI_FormNew( "HarbourBuilder iOS", 375, 667 )
   UI_SetFormColor( 0xFFFFFF )    /* white background */

   ::hLabel := UI_LabelNew( ::hForm, "Hello from Harbour!", 40, 80, 295, 40 )
   UI_SetCtrlColor( ::hLabel, 0xFFFFCC )   /* light yellow (BGR) */
   UI_SetCtrlFont( ::hLabel, "Helvetica", 24 )

   ::hEdit := UI_EditNew( ::hForm, "Type here...", 40, 160, 295, 40 )

   ::hButton := UI_ButtonNew( ::hForm, "Click Me", 40, 240, 295, 50 )
   UI_SetCtrlColor( ::hButton, 0xCC9966 )   /* olive (BGR) */

   UI_OnClick( ::hButton, {|| ::OnButtonClick() } )

RETURN Self

METHOD Run() CLASS iOSApp
   UI_FormRun( ::hForm )
RETURN Self

METHOD OnButtonClick() CLASS iOSApp

   LOCAL cText

   ::nClicks++
   cText := UI_GetText( ::hEdit )

   IF Empty( cText )
      cText := "(empty)"
   ENDIF

   UI_SetText( ::hLabel, "Click #" + AllTrim( Str( ::nClicks ) ) + ": " + cText )

RETURN Self
