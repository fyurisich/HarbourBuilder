/* Form1.prg - iOS Form Definition */

#include "hbclass.ch"

CLASS TFormIOS

   DATA hForm
   DATA hTitleLabel
   DATA hNameLabel
   DATA hNameEdit
   DATA hOkButton
   DATA hCancelButton

   METHOD New( cTitle, nWidth, nHeight )
   METHOD Activate()

ENDCLASS

METHOD New( cTitle, nWidth, nHeight ) CLASS TFormIOS

   DEFAULT cTitle TO "Form", nWidth TO 375, nHeight TO 667

   ::hForm := UI_FormNew( cTitle, nWidth, nHeight )
   UI_SetFormColor( 0xFFFFFF )

   /* Title */
   ::hTitleLabel := UI_LabelNew( ::hForm, cTitle, 20, 40, 335, 35 )
   UI_SetCtrlFont( ::hTitleLabel, "Helvetica-Bold", 22 )
   UI_SetCtrlColor( ::hTitleLabel, -1 )   /* transparent */

   /* Name field */
   ::hNameLabel := UI_LabelNew( ::hForm, "Name:", 20, 100, 100, 30 )
   ::hNameEdit  := UI_EditNew( ::hForm, "", 130, 100, 225, 30 )

   /* Buttons */
   ::hOkButton     := UI_ButtonNew( ::hForm, "OK", 20, 160, 160, 40 )
   ::hCancelButton := UI_ButtonNew( ::hForm, "Cancel", 195, 160, 160, 40 )

   UI_OnClick( ::hOkButton,     {|| ::OnOK() } )
   UI_OnClick( ::hCancelButton, {|| ::OnCancel() } )

RETURN Self

METHOD Activate() CLASS TFormIOS
   UI_FormRun( ::hForm )
RETURN Self

METHOD OnOK() CLASS TFormIOS
   LOCAL cName := UI_GetText( ::hNameEdit )
   UI_SetText( ::hTitleLabel, "Hello, " + IfEmpty( cName, "World" ) + "!" )
RETURN Self

METHOD OnCancel() CLASS TFormIOS
   UI_SetText( ::hNameEdit, "" )
   UI_SetText( ::hTitleLabel, "Cancelled" )
RETURN Self
