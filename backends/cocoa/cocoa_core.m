/*
 * cocoa_core.m - Cocoa/AppKit implementation of hbcpp framework for macOS
 * Replaces the Win32 C++ core (tcontrol.cpp, tform.cpp, tcontrols.cpp, hbbridge.cpp)
 *
 * Provides the same HB_FUNC bridge interface so Harbour code (classes.prg) works unchanged.
 */

#import <Cocoa/Cocoa.h>
#include <hbapi.h>
#include <hbapiitm.h>
#include <hbapicls.h>
#include <hbstack.h>
#include <hbvm.h>
#include <string.h>
#include <stdio.h>

/* Control types - must match original */
#define CT_FORM       0
#define CT_LABEL      1
#define CT_EDIT       2
#define CT_BUTTON     3
#define CT_CHECKBOX   4
#define CT_COMBOBOX   5
#define CT_GROUPBOX   6
#define CT_TOOLBAR    9

#define MAX_CHILDREN  256

/* ======================================================================
 * NSApp initialization
 * ====================================================================== */

static BOOL s_appInitialized = NO;

static void EnsureNSApp( void )
{
   if( !s_appInitialized )
   {
      [NSApplication sharedApplication];
      [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

      NSMenu * menuBar = [[NSMenu alloc] init];
      NSMenuItem * appMenuItem = [[NSMenuItem alloc] init];
      NSMenu * appMenu = [[NSMenu alloc] initWithTitle:@"App"];
      [appMenu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
      [appMenuItem setSubmenu:appMenu];
      [menuBar addItem:appMenuItem];
      [NSApp setMainMenu:menuBar];

      s_appInitialized = YES;
   }
}

/* ======================================================================
 * Flipped NSView (top-left origin like Win32)
 * ====================================================================== */

@interface HBFlippedView : NSView
@end
@implementation HBFlippedView
- (BOOL)isFlipped { return YES; }
@end

/* ======================================================================
 * ALL @interface declarations (full definitions before any @implementation)
 * ====================================================================== */

/* --- HBControl --- */
@interface HBControl : NSObject
{
@public
   char FClassName[32];
   char FName[64];
   char FText[256];
   int  FLeft, FTop, FWidth, FHeight;
   BOOL FVisible, FEnabled, FTabStop;
   int  FControlType;
   NSView * FView;
   NSFont * FFont;
   NSColor * FBgColor;
   unsigned int FClrPane;

   PHB_ITEM FOnClick, FOnChange, FOnInit, FOnClose;

   HBControl * FCtrlParent;
   HBControl * FChildren[MAX_CHILDREN];
   int FChildCount;
}
- (void)addChild:(HBControl *)child;
- (void)setText:(const char *)text;
- (void)createViewInParent:(NSView *)parentView;
- (void)updateViewFrame;
- (void)setEvent:(const char *)event block:(PHB_ITEM)block;
- (void)fireEvent:(PHB_ITEM)block;
- (void)releaseEvents;
- (void)applyFont;
@end

/* --- HBForm --- */
@interface HBForm : HBControl <NSWindowDelegate>
{
@public
   NSWindow * FWindow;
   NSFont *   FFormFont;
   BOOL       FCenter;
   BOOL       FSizable;
   BOOL       FAppBar;
   int        FModalResult;
   BOOL       FRunning;
   BOOL       FDesignMode;
   HBControl * FSelected[MAX_CHILDREN];
   int        FSelCount;
   BOOL       FDragging, FResizing;
   int        FResizeHandle;
   int        FDragStartX, FDragStartY;
   PHB_ITEM   FOnSelChange;
   NSView *   FOverlayView;
   HBFlippedView * FContentView;
   /* Toolbar */
   HBToolBar * FToolBar;
   int         FClientTop;
   /* Menu */
   PHB_ITEM    FMenuActions[MAX_MENUITEMS];
   int         FMenuItemCount;
}
- (void)run;
- (void)showOnly;  /* Create + show without entering run loop */
- (void)close;
- (void)center;
- (void)createAllChildren;
- (void)setDesignMode:(BOOL)design;
- (HBControl *)hitTestControl:(NSPoint)point;
- (int)hitTestHandle:(NSPoint)point;
- (void)selectControl:(HBControl *)ctrl add:(BOOL)add;
- (void)clearSelection;
- (BOOL)isSelected:(HBControl *)ctrl;
- (void)notifySelChange;
@end

/* --- HBLabel --- */
@interface HBLabel : HBControl
@end

/* --- HBEdit --- */
@interface HBEdit : HBControl
{
@public
   BOOL FReadOnly, FPassword;
}
@end

/* --- HBButton --- */
@interface HBButton : HBControl
{
@public
   BOOL FDefault, FCancel;
}
- (void)buttonClicked:(id)sender;
@end

/* --- HBCheckBox --- */
@interface HBCheckBox : HBControl
{
@public
   BOOL FChecked;
}
- (void)setChecked:(BOOL)checked;
@end

/* --- HBComboBox --- */
@interface HBComboBox : HBControl
{
@public
   int  FItemIndex;
   char FItems[32][64];
   int  FItemCount;
}
- (void)addItem:(const char *)item;
- (void)setItemIndex:(int)idx;
@end

/* --- HBGroupBox --- */
@interface HBGroupBox : HBControl
@end

/* --- HBToolBar --- */
#define MAX_TOOLBTNS  64
#define TOOLBAR_BTN_ID_BASE 100
#define MENU_ID_BASE        1000
#define MAX_MENUITEMS       128

@interface HBToolBar : HBControl
{
@public
   char     FBtnTexts[MAX_TOOLBTNS][32];
   char     FBtnTooltips[MAX_TOOLBTNS][128];
   BOOL     FBtnSeparator[MAX_TOOLBTNS];
   PHB_ITEM FBtnOnClick[MAX_TOOLBTNS];
   int      FBtnCount;
}
- (int)addButton:(const char *)text tooltip:(const char *)tooltip;
- (void)addSeparator;
- (void)setBtnClick:(int)idx block:(PHB_ITEM)block;
- (void)doCommand:(int)idx;
- (int)barHeight;
@end

/* --- HBOverlayView --- */
@interface HBOverlayView : NSView
{
@public
   HBForm * __unsafe_unretained form;
   BOOL isRubberBand;
   NSPoint rubberOrigin, rubberCurrent;
}
@end

/* ======================================================================
 * ALL @implementation sections
 * ====================================================================== */

/* --- HBControl implementation --- */

@implementation HBControl

- (instancetype)init
{
   self = [super init];
   if( self ) {
      strcpy( FClassName, "TControl" );
      FName[0] = 0; FText[0] = 0;
      FLeft = 0; FTop = 0; FWidth = 80; FHeight = 24;
      FVisible = YES; FEnabled = YES; FTabStop = YES;
      FControlType = 0; FView = nil; FFont = nil; FBgColor = nil;
      FClrPane = 0xFFFFFFFF;
      FOnClick = NULL; FOnChange = NULL; FOnInit = NULL; FOnClose = NULL;
      FCtrlParent = nil; FChildCount = 0;
      memset( FChildren, 0, sizeof(FChildren) );
   }
   return self;
}

- (void)dealloc { [self releaseEvents]; }

- (void)addChild:(HBControl *)child
{
   if( FChildCount < MAX_CHILDREN ) {
      FChildren[FChildCount++] = child;
      child->FCtrlParent = self;
   }
}

- (void)setText:(const char *)text
{
   strncpy( FText, text, sizeof(FText) - 1 );
   FText[sizeof(FText) - 1] = 0;
}

- (void)createViewInParent:(NSView *)parentView { /* override */ }

- (void)updateViewFrame
{
   if( FView ) [FView setFrame:NSMakeRect( FLeft, FTop, FWidth, FHeight )];
}

- (void)applyFont
{
   if( FFont && FView && [FView respondsToSelector:@selector(setFont:)] )
      [(id)FView setFont:FFont];
}

- (void)setEvent:(const char *)event block:(PHB_ITEM)block
{
   PHB_ITEM * ppTarget = NULL;
   if( strcasecmp( event, "OnClick" ) == 0 )       ppTarget = &FOnClick;
   else if( strcasecmp( event, "OnChange" ) == 0 )  ppTarget = &FOnChange;
   else if( strcasecmp( event, "OnInit" ) == 0 )    ppTarget = &FOnInit;
   else if( strcasecmp( event, "OnClose" ) == 0 )   ppTarget = &FOnClose;
   if( ppTarget ) {
      if( *ppTarget ) hb_itemRelease( *ppTarget );
      *ppTarget = hb_itemNew( block );
   }
}

- (void)fireEvent:(PHB_ITEM)block
{
   if( block && HB_IS_BLOCK( block ) ) {
      hb_vmPushEvalSym();
      hb_vmPush( block );
      hb_vmPushNumInt( (HB_PTRUINT) self );
      hb_vmSend( 1 );
   }
}

- (void)releaseEvents
{
   if( FOnClick )  { hb_itemRelease( FOnClick );  FOnClick = NULL; }
   if( FOnChange ) { hb_itemRelease( FOnChange ); FOnChange = NULL; }
   if( FOnInit )   { hb_itemRelease( FOnInit );   FOnInit = NULL; }
   if( FOnClose )  { hb_itemRelease( FOnClose );  FOnClose = NULL; }
}

@end

/* --- HBLabel implementation --- */

@implementation HBLabel

- (instancetype)init
{
   self = [super init];
   if( self ) {
      strcpy( FClassName, "TLabel" );
      FControlType = CT_LABEL; FWidth = 80; FHeight = 15; FTabStop = NO;
      strcpy( FText, "Label" );
   }
   return self;
}

- (void)createViewInParent:(NSView *)parentView
{
   NSTextField * tf = [[NSTextField alloc] initWithFrame:
      NSMakeRect( FLeft, FTop, FWidth, FHeight )];
   [tf setStringValue:[NSString stringWithUTF8String:FText]];
   [tf setBezeled:NO]; [tf setDrawsBackground:NO];
   [tf setEditable:NO]; [tf setSelectable:NO];
   [tf setTextColor:[NSColor blackColor]];
   if( FFont ) [tf setFont:FFont];
   [parentView addSubview:tf];
   FView = tf;
}

@end

/* --- HBEdit implementation --- */

@implementation HBEdit

- (instancetype)init
{
   self = [super init];
   if( self ) {
      strcpy( FClassName, "TEdit" );
      FControlType = CT_EDIT; FWidth = 200; FHeight = 24;
      FReadOnly = NO; FPassword = NO;
   }
   return self;
}

- (void)createViewInParent:(NSView *)parentView
{
   NSTextField * tf;
   if( FPassword )
      tf = [[NSSecureTextField alloc] initWithFrame:NSMakeRect( FLeft, FTop, FWidth, FHeight )];
   else
      tf = [[NSTextField alloc] initWithFrame:NSMakeRect( FLeft, FTop, FWidth, FHeight )];
   [tf setStringValue:[NSString stringWithUTF8String:FText]];
   [tf setBezeled:YES]; [tf setBezelStyle:NSTextFieldSquareBezel];
   [tf setEditable:!FReadOnly];
   [tf setTextColor:[NSColor blackColor]];
   if( FFont ) [tf setFont:FFont];
   [parentView addSubview:tf];
   FView = tf;
}

@end

/* --- HBButton implementation --- */

@implementation HBButton

- (instancetype)init
{
   self = [super init];
   if( self ) {
      strcpy( FClassName, "TButton" );
      FControlType = CT_BUTTON; FWidth = 88; FHeight = 26;
      FDefault = NO; FCancel = NO;
   }
   return self;
}

- (void)createViewInParent:(NSView *)parentView
{
   NSButton * btn = [[NSButton alloc] initWithFrame:NSMakeRect( FLeft, FTop, FWidth, FHeight )];
   NSString * title = [[NSString stringWithUTF8String:FText]
      stringByReplacingOccurrencesOfString:@"&" withString:@""];
   [btn setTitle:title];
   [btn setBezelStyle:NSBezelStyleRounded];
   [btn setButtonType:NSButtonTypeMomentaryPushIn];
   if( FDefault ) [btn setKeyEquivalent:@"\r"];
   if( FCancel )  [btn setKeyEquivalent:@"\033"];
   if( FFont ) [btn setFont:FFont];
   [btn setTarget:self]; [btn setAction:@selector(buttonClicked:)];
   [parentView addSubview:btn];
   FView = btn;
}

- (void)buttonClicked:(id)sender
{
   [self fireEvent:FOnClick];

   /* Find parent form */
   HBControl * p = FCtrlParent;
   while( p && p->FControlType != CT_FORM ) p = p->FCtrlParent;

   if( p ) {
      HBForm * frm = (HBForm *)p;
      if( FDefault ) frm->FModalResult = 1;
      else if( FCancel ) frm->FModalResult = 2;
      if( FDefault || FCancel ) [frm close];
   }
}

@end

/* --- HBCheckBox implementation --- */

@implementation HBCheckBox

- (instancetype)init
{
   self = [super init];
   if( self ) {
      strcpy( FClassName, "TCheckBox" );
      FControlType = CT_CHECKBOX; FWidth = 150; FHeight = 19; FChecked = NO;
   }
   return self;
}

- (void)createViewInParent:(NSView *)parentView
{
   NSButton * btn = [[NSButton alloc] initWithFrame:NSMakeRect( FLeft, FTop, FWidth, FHeight )];
   [btn setButtonType:NSButtonTypeSwitch];
   [btn setTitle:[NSString stringWithUTF8String:FText]];
   NSMutableAttributedString * cbTitle = [[NSMutableAttributedString alloc]
      initWithString:[NSString stringWithUTF8String:FText]
      attributes:@{ NSForegroundColorAttributeName: [NSColor blackColor] }];
   [btn setAttributedTitle:cbTitle];
   if( FChecked ) [btn setState:NSControlStateValueOn];
   if( FFont ) [btn setFont:FFont];
   [parentView addSubview:btn];
   FView = btn;
}

- (void)setChecked:(BOOL)checked
{
   FChecked = checked;
   if( FView ) [(NSButton *)FView setState:checked ? NSControlStateValueOn : NSControlStateValueOff];
}

@end

/* --- HBComboBox implementation --- */

@implementation HBComboBox

- (instancetype)init
{
   self = [super init];
   if( self ) {
      strcpy( FClassName, "TComboBox" );
      FControlType = CT_COMBOBOX; FWidth = 175; FHeight = 26;
      FItemIndex = 0; FItemCount = 0;
      memset( FItems, 0, sizeof(FItems) );
   }
   return self;
}

- (void)createViewInParent:(NSView *)parentView
{
   /* In Win32, combobox height is the dropdown height, not the control height.
      NSPopUpButton has a fixed intrinsic height (~26px). Use that instead. */
   CGFloat popupHeight = 26;
   NSPopUpButton * popup = [[NSPopUpButton alloc] initWithFrame:
      NSMakeRect( FLeft, FTop, FWidth, popupHeight ) pullsDown:NO];
   for( int i = 0; i < FItemCount; i++ )
      [popup addItemWithTitle:[NSString stringWithUTF8String:FItems[i]]];
   if( FItemIndex >= 0 && FItemIndex < FItemCount )
      [popup selectItemAtIndex:FItemIndex];
   if( FFont ) [popup setFont:FFont];
   [popup setTarget:self]; [popup setAction:@selector(comboChanged:)];
   [parentView addSubview:popup];
   FView = popup;
   FHeight = (int)popupHeight;
}

- (void)comboChanged:(id)sender
{
   FItemIndex = (int)[(NSPopUpButton *)FView indexOfSelectedItem];
   [self fireEvent:FOnChange];
}

- (void)addItem:(const char *)item
{
   if( FItemCount < 32 ) strncpy( FItems[FItemCount++], item, 63 );
   if( FView ) [(NSPopUpButton *)FView addItemWithTitle:[NSString stringWithUTF8String:item]];
}

- (void)setItemIndex:(int)idx
{
   FItemIndex = idx;
   if( FView && idx >= 0 ) [(NSPopUpButton *)FView selectItemAtIndex:idx];
}

@end

/* --- HBGroupBox implementation --- */

@implementation HBGroupBox

- (instancetype)init
{
   self = [super init];
   if( self ) {
      strcpy( FClassName, "TGroupBox" );
      FControlType = CT_GROUPBOX; FWidth = 200; FHeight = 100; FTabStop = NO;
   }
   return self;
}

- (void)createViewInParent:(NSView *)parentView
{
   NSBox * box = [[NSBox alloc] initWithFrame:NSMakeRect( FLeft, FTop, FWidth, FHeight )];
   [box setTitle:[NSString stringWithUTF8String:FText]];
   [box setTitlePosition:NSAtTop];
   [box setBorderColor:[NSColor grayColor]];
   if( FFont ) [box setTitleFont:FFont];
   [parentView addSubview:box];
   FView = box;
}

@end

/* --- HBToolBar implementation --- */

@implementation HBToolBar

- (instancetype)init
{
   self = [super init];
   if( self ) {
      strcpy( FClassName, "TToolBar" );
      FControlType = CT_TOOLBAR; FBtnCount = 0;
      memset( FBtnOnClick, 0, sizeof(FBtnOnClick) );
   }
   return self;
}

- (void)dealloc
{
   for( int i = 0; i < FBtnCount; i++ )
      if( FBtnOnClick[i] ) hb_itemRelease( FBtnOnClick[i] );
}

- (void)createViewInParent:(NSView *)parentView
{
   /* Create a horizontal stack of buttons as a toolbar strip */
   NSRect tbFrame = NSMakeRect( 0, 0, FWidth > 0 ? FWidth : 800, 30 );
   NSView * toolbar = [[HBFlippedView alloc] initWithFrame:tbFrame];
   [toolbar setAutoresizingMask:NSViewWidthSizable];

   /* Light gray background */
   toolbar.wantsLayer = YES;
   toolbar.layer.backgroundColor = [[NSColor colorWithCalibratedWhite:0.92 alpha:1.0] CGColor];

   int xPos = 4;
   for( int i = 0; i < FBtnCount; i++ )
   {
      if( FBtnSeparator[i] ) {
         /* Separator: small vertical line */
         NSBox * sep = [[NSBox alloc] initWithFrame:NSMakeRect( xPos, 2, 1, 26 )];
         [sep setBoxType:NSBoxSeparator];
         [toolbar addSubview:sep];
         xPos += 8;
      } else {
         NSButton * btn = [[NSButton alloc] initWithFrame:NSMakeRect( xPos, 2, 0, 26 )];
         [btn setTitle:[NSString stringWithUTF8String:FBtnTexts[i]]];
         [btn setToolTip:[NSString stringWithUTF8String:FBtnTooltips[i]]];
         [btn setBezelStyle:NSBezelStyleTexturedRounded];
         [btn setTarget:self];
         [btn setAction:@selector(toolBtnClicked:)];
         [btn setTag:i];
         [btn sizeToFit];
         NSRect f = [btn frame]; f.origin.x = xPos; f.origin.y = 2; [btn setFrame:f];
         [toolbar addSubview:btn];
         xPos += (int)f.size.width + 2;
      }
   }

   [parentView addSubview:toolbar];
   FView = toolbar;
}

- (void)toolBtnClicked:(id)sender
{
   int idx = (int)[sender tag];
   [self doCommand:idx];
}

- (int)addButton:(const char *)text tooltip:(const char *)tooltip
{
   if( FBtnCount >= MAX_TOOLBTNS ) return -1;
   int idx = FBtnCount++;
   strncpy( FBtnTexts[idx], text, 31 ); FBtnTexts[idx][31] = 0;
   strncpy( FBtnTooltips[idx], tooltip, 127 ); FBtnTooltips[idx][127] = 0;
   FBtnSeparator[idx] = NO;
   FBtnOnClick[idx] = NULL;
   return idx;
}

- (void)addSeparator
{
   if( FBtnCount >= MAX_TOOLBTNS ) return;
   FBtnSeparator[FBtnCount] = YES;
   FBtnTexts[FBtnCount][0] = 0;
   FBtnTooltips[FBtnCount][0] = 0;
   FBtnOnClick[FBtnCount] = NULL;
   FBtnCount++;
}

- (void)setBtnClick:(int)idx block:(PHB_ITEM)block
{
   if( idx < 0 || idx >= FBtnCount ) return;
   if( FBtnOnClick[idx] ) hb_itemRelease( FBtnOnClick[idx] );
   FBtnOnClick[idx] = hb_itemNew( block );
}

- (void)doCommand:(int)idx
{
   if( idx >= 0 && idx < FBtnCount && FBtnOnClick[idx] ) {
      hb_vmPushEvalSym();
      hb_vmPush( FBtnOnClick[idx] );
      hb_vmSend( 0 );
   }
}

- (int)barHeight { return 30; }

@end

/* --- HBOverlayView implementation --- */

@implementation HBOverlayView

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }

- (NSView *)hitTest:(NSPoint)point
{
   if( form && form->FDesignMode ) return self;
   return nil;
}

- (void)drawRect:(NSRect)dirtyRect
{
   if( !form ) return;

   NSColor * handleColor = [NSColor colorWithCalibratedRed:0.0 green:0.47 blue:0.84 alpha:1.0];

   for( int i = 0; i < form->FSelCount; i++ )
   {
      HBControl * ctrl = form->FSelected[i];
      NSRect bounds = NSMakeRect( ctrl->FLeft, ctrl->FTop, ctrl->FWidth, ctrl->FHeight );

      /* Dashed border */
      NSBezierPath * border = [NSBezierPath bezierPathWithRect:NSInsetRect( bounds, -1, -1 )];
      CGFloat pattern[] = { 4, 2 };
      [border setLineDash:pattern count:2 phase:0];
      [border setLineWidth:1.0];
      [handleColor set];
      [border stroke];

      /* 8 handles */
      int px = ctrl->FLeft, py = ctrl->FTop, pw = ctrl->FWidth, ph = ctrl->FHeight;
      NSPoint handles[8] = {
         { px-3, py-3 }, { px+pw/2-3, py-3 }, { px+pw-3, py-3 },
         { px+pw-3, py+ph/2-3 }, { px+pw-3, py+ph-3 },
         { px+pw/2-3, py+ph-3 }, { px-3, py+ph-3 }, { px-3, py+ph/2-3 }
      };

      for( int j = 0; j < 8; j++ ) {
         NSRect hr = NSMakeRect( handles[j].x, handles[j].y, 7, 7 );
         [[NSColor whiteColor] setFill]; NSRectFill( hr );
         [handleColor setStroke]; [NSBezierPath strokeRect:hr];
      }
   }

   /* Rubber band */
   if( isRubberBand ) {
      CGFloat rx = fmin(rubberOrigin.x, rubberCurrent.x);
      CGFloat ry = fmin(rubberOrigin.y, rubberCurrent.y);
      CGFloat rw = fabs(rubberCurrent.x - rubberOrigin.x);
      CGFloat rh = fabs(rubberCurrent.y - rubberOrigin.y);
      NSBezierPath * rbPath = [NSBezierPath bezierPathWithRect:NSMakeRect(rx,ry,rw,rh)];
      CGFloat pat[] = { 3, 3 };
      [rbPath setLineDash:pat count:2 phase:0];
      [handleColor set]; [rbPath stroke];
      [[handleColor colorWithAlphaComponent:0.1] setFill];
      NSRectFillUsingOperation( NSMakeRect(rx,ry,rw,rh), NSCompositingOperationSourceOver );
   }
}

- (void)mouseDown:(NSEvent *)event
{
   if( !form || !form->FDesignMode ) return;
   NSPoint pt = [self convertPoint:[event locationInWindow] fromView:nil];
   BOOL isShift = ([event modifierFlags] & NSEventModifierFlagShift) != 0;

   int nHandle = [form hitTestHandle:pt];
   if( nHandle >= 0 ) {
      form->FResizing = YES; form->FResizeHandle = nHandle;
      form->FDragStartX = (int)pt.x; form->FDragStartY = (int)pt.y;
      return;
   }

   HBControl * hit = [form hitTestControl:pt];
   if( hit ) {
      if( isShift ) {
         if( [form isSelected:hit] ) {
            for( int k = 0; k < form->FSelCount; k++ )
               if( form->FSelected[k] == hit ) {
                  form->FSelected[k] = form->FSelected[--form->FSelCount]; break;
               }
            [self setNeedsDisplay:YES];
         } else
            [form selectControl:hit add:YES];
      } else {
         if( ![form isSelected:hit] ) [form selectControl:hit add:NO];
         form->FDragging = YES;
         form->FDragStartX = (int)pt.x; form->FDragStartY = (int)pt.y;
      }
   } else {
      [form clearSelection];
      isRubberBand = YES;
      rubberOrigin = pt; rubberCurrent = pt;
   }
}

- (void)mouseDragged:(NSEvent *)event
{
   if( !form || !form->FDesignMode ) return;
   NSPoint pt = [self convertPoint:[event locationInWindow] fromView:nil];

   if( isRubberBand ) {
      rubberCurrent = pt; [self setNeedsDisplay:YES]; return;
   }

   if( form->FResizing && form->FSelCount > 0 ) {
      int dx = (int)pt.x - form->FDragStartX, dy = (int)pt.y - form->FDragStartY;
      HBControl * p = form->FSelected[0];
      int nl = p->FLeft, nt = p->FTop, nw = p->FWidth, nh = p->FHeight;
      dx = (dx/4)*4; dy = (dy/4)*4;
      if( dx == 0 && dy == 0 ) return;
      switch( form->FResizeHandle ) {
         case 0: nl+=dx; nt+=dy; nw-=dx; nh-=dy; break;
         case 1: nt+=dy; nh-=dy; break;
         case 2: nw+=dx; nt+=dy; nh-=dy; break;
         case 3: nw+=dx; break;
         case 4: nw+=dx; nh+=dy; break;
         case 5: nh+=dy; break;
         case 6: nl+=dx; nw-=dx; nh+=dy; break;
         case 7: nl+=dx; nw-=dx; break;
      }
      if( nw < 20 ) { nw = 20; nl = p->FLeft; }
      if( nh < 10 ) { nh = 10; nt = p->FTop; }
      p->FLeft = nl; p->FTop = nt; p->FWidth = nw; p->FHeight = nh;
      [p updateViewFrame];
      form->FDragStartX += dx; form->FDragStartY += dy;
      [self setNeedsDisplay:YES]; [form notifySelChange];
      return;
   }

   if( form->FDragging && form->FSelCount > 0 ) {
      int dx = (int)pt.x - form->FDragStartX, dy = (int)pt.y - form->FDragStartY;
      dx = (dx/4)*4; dy = (dy/4)*4;
      if( dx == 0 && dy == 0 ) return;
      for( int i = 0; i < form->FSelCount; i++ ) {
         form->FSelected[i]->FLeft += dx; form->FSelected[i]->FTop += dy;
         [form->FSelected[i] updateViewFrame];
      }
      form->FDragStartX += dx; form->FDragStartY += dy;
      [self setNeedsDisplay:YES]; [form notifySelChange];
   }
}

- (void)mouseUp:(NSEvent *)event
{
   if( !form || !form->FDesignMode ) return;

   if( isRubberBand ) {
      isRubberBand = NO;
      CGFloat rx1 = fmin(rubberOrigin.x, rubberCurrent.x);
      CGFloat ry1 = fmin(rubberOrigin.y, rubberCurrent.y);
      CGFloat rx2 = fmax(rubberOrigin.x, rubberCurrent.x);
      CGFloat ry2 = fmax(rubberOrigin.y, rubberCurrent.y);
      [form clearSelection];
      for( int i = 0; i < form->FChildCount; i++ ) {
         HBControl * p = form->FChildren[i];
         if( p->FControlType == CT_GROUPBOX ) continue;
         if( p->FLeft + p->FWidth > rx1 && p->FLeft < rx2 &&
             p->FTop + p->FHeight > ry1 && p->FTop < ry2 )
            if( form->FSelCount < MAX_CHILDREN )
               form->FSelected[form->FSelCount++] = p;
      }
      [self setNeedsDisplay:YES]; [form notifySelChange];
      return;
   }

   if( form->FDragging || form->FResizing ) {
      form->FDragging = NO; form->FResizing = NO; form->FResizeHandle = -1;
      [self setNeedsDisplay:YES]; [form notifySelChange];
   }
}

- (void)keyDown:(NSEvent *)event
{
   if( !form || !form->FDesignMode ) return;
   unsigned short keyCode = [event keyCode];

   if( (keyCode == 51 || keyCode == 117) && form->FSelCount > 0 ) {
      for( int i = 0; i < form->FSelCount; i++ )
         if( form->FSelected[i]->FView ) {
            [form->FSelected[i]->FView removeFromSuperview];
            form->FSelected[i]->FView = nil;
         }
      [form clearSelection]; return;
   }

   NSString * chars = [event charactersIgnoringModifiers];
   if( [chars length] > 0 && form->FSelCount > 0 ) {
      unichar ch = [chars characterAtIndex:0];
      int dx = 0, dy = 0, step = ([event modifierFlags] & NSEventModifierFlagShift) ? 1 : 4;
      switch( ch ) {
         case NSLeftArrowFunctionKey:  dx = -step; break;
         case NSRightArrowFunctionKey: dx = step;  break;
         case NSUpArrowFunctionKey:    dy = -step; break;
         case NSDownArrowFunctionKey:  dy = step;  break;
         default: [super keyDown:event]; return;
      }
      for( int i = 0; i < form->FSelCount; i++ ) {
         form->FSelected[i]->FLeft += dx; form->FSelected[i]->FTop += dy;
         [form->FSelected[i] updateViewFrame];
      }
      [self setNeedsDisplay:YES]; [form notifySelChange];
   }
}

@end

/* --- HBForm implementation --- */

@implementation HBForm

- (instancetype)init
{
   self = [super init];
   if( self ) {
      strcpy( FClassName, "TForm" );
      FControlType = CT_FORM;
      FFormFont = [NSFont systemFontOfSize:12];
      FFont = FFormFont;
      FCenter = YES; FSizable = NO; FAppBar = NO; FModalResult = 0; FRunning = NO; FDesignMode = NO;
      FSelCount = 0; FDragging = NO; FResizing = NO; FResizeHandle = -1;
      FOnSelChange = NULL; FOverlayView = nil; FContentView = nil;
      FToolBar = nil; FClientTop = 0; FMenuItemCount = 0;
      memset( FSelected, 0, sizeof(FSelected) );
      memset( FMenuActions, 0, sizeof(FMenuActions) );
      FWidth = 470; FHeight = 400;
      strcpy( FText, "New Form" );
      FClrPane = 0x00F0F0F0;
      FWindow = nil;
   }
   return self;
}

- (void)dealloc
{
   if( FOnSelChange ) { hb_itemRelease( FOnSelChange ); FOnSelChange = NULL; }
   for( int i = 0; i < FMenuItemCount; i++ )
      if( FMenuActions[i] ) { hb_itemRelease( FMenuActions[i] ); FMenuActions[i] = NULL; }
}

- (void)run
{
   EnsureNSApp();

   [self createWindowWithRunLoop:YES];
}

- (void)createWindowWithRunLoop:(BOOL)enterLoop
{
   EnsureNSApp();

   NSRect frame = NSMakeRect( 0, 0, FWidth, FHeight );
   NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
   if( FAppBar )
      style |= NSWindowStyleMaskMiniaturizable;  /* no resize for appbar */
   else if( FSizable )
      style |= NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable;
   FWindow = [[NSWindow alloc] initWithContentRect:frame
      styleMask:style
      backing:NSBackingStoreBuffered defer:NO];
   [FWindow setTitle:[NSString stringWithUTF8String:FText]];
   [FWindow setDelegate:self];
   [FWindow setReleasedWhenClosed:NO];

   FContentView = [[HBFlippedView alloc] initWithFrame:[[FWindow contentView] bounds]];
   [FContentView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
   /* Force light appearance to avoid dark mode white-on-dark text */
   if( [NSAppearance respondsToSelector:@selector(appearanceNamed:)] )
      [FWindow setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
   [FWindow setBackgroundColor:[NSColor colorWithCalibratedRed:0.94 green:0.94 blue:0.94 alpha:1.0]];
   [FWindow setContentView:FContentView];

   [self createAllChildren];

   if( FDesignMode ) {
      HBOverlayView * ov = [[HBOverlayView alloc] initWithFrame:[FContentView bounds]];
      ov->form = self;
      [ov setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
      [FContentView addSubview:ov];
      FOverlayView = ov;
      [FWindow makeFirstResponder:ov];
   }

   if( FCenter ) [self center];
   else if( !FCenter ) {
      NSRect screenFrame = [[NSScreen mainScreen] frame];
      NSPoint origin;
      origin.x = FLeft;
      origin.y = screenFrame.size.height - FTop - FHeight;
      [FWindow setFrameOrigin:origin];
   }
   [FWindow makeKeyAndOrderFront:nil];
   [NSApp activateIgnoringOtherApps:YES];

   FRunning = YES;
   if( enterLoop ) {
      [NSApp run];
      FRunning = NO;
   }
}

- (void)showOnly
{
   [self createWindowWithRunLoop:NO];
}

- (void)close
{
   FRunning = NO;
   [FWindow close];
}

- (void)center { if( FWindow ) [FWindow center]; }

- (void)createAllChildren
{
   /* Toolbar first */
   if( FToolBar ) {
      FToolBar->FWidth = FWidth;
      [FToolBar createViewInParent:FContentView];
      FClientTop = [FToolBar barHeight];
   }

   /* GroupBoxes first */
   for( int i = 0; i < FChildCount; i++ )
      if( FChildren[i]->FControlType == CT_GROUPBOX ) {
         FChildren[i]->FFont = FFormFont;
         FChildren[i]->FTop += FClientTop;
         [FChildren[i] createViewInParent:FContentView];
      }
   for( int i = 0; i < FChildCount; i++ )
      if( FChildren[i]->FControlType != CT_GROUPBOX &&
          FChildren[i]->FControlType != CT_TOOLBAR ) {
         FChildren[i]->FFont = FFormFont;
         FChildren[i]->FTop += FClientTop;
         [FChildren[i] createViewInParent:FContentView];
      }
}

- (void)setDesignMode:(BOOL)design
{
   FDesignMode = design;
   [self clearSelection];
   if( design && FContentView && !FOverlayView ) {
      HBOverlayView * ov = [[HBOverlayView alloc] initWithFrame:[FContentView bounds]];
      ov->form = self;
      [ov setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
      [FContentView addSubview:ov];
      FOverlayView = ov;
      [FWindow makeFirstResponder:ov];
   }
}

- (HBControl *)hitTestControl:(NSPoint)point
{
   int border = 8;
   HBControl * groupHit = nil;
   for( int i = FChildCount - 1; i >= 0; i-- ) {
      HBControl * p = FChildren[i];
      int l = p->FLeft, t = p->FTop, r = l + p->FWidth, b = t + p->FHeight;
      if( point.x >= l && point.x <= r && point.y >= t && point.y <= b ) {
         if( p->FControlType == CT_GROUPBOX ) {
            if( point.y <= t+18 || point.x <= l+border || point.x >= r-border || point.y >= b-border )
               if( !groupHit ) groupHit = p;
         } else
            return p;
      }
   }
   return groupHit;
}

- (int)hitTestHandle:(NSPoint)point
{
   for( int i = 0; i < FSelCount; i++ ) {
      HBControl * p = FSelected[i];
      int px=p->FLeft, py=p->FTop, pw=p->FWidth, ph=p->FHeight;
      int hx[8], hy[8];
      hx[0]=px-3; hy[0]=py-3; hx[1]=px+pw/2-3; hy[1]=py-3;
      hx[2]=px+pw-3; hy[2]=py-3; hx[3]=px+pw-3; hy[3]=py+ph/2-3;
      hx[4]=px+pw-3; hy[4]=py+ph-3; hx[5]=px+pw/2-3; hy[5]=py+ph-3;
      hx[6]=px-3; hy[6]=py+ph-3; hx[7]=px-3; hy[7]=py+ph/2-3;
      for( int j = 0; j < 8; j++ )
         if( point.x >= hx[j] && point.x <= hx[j]+7 && point.y >= hy[j] && point.y <= hy[j]+7 )
            return j;
   }
   return -1;
}

- (void)selectControl:(HBControl *)ctrl add:(BOOL)add
{
   if( !add ) { FSelCount = 0; memset( FSelected, 0, sizeof(FSelected) ); }
   if( ctrl && FSelCount < MAX_CHILDREN && ![self isSelected:ctrl] )
      FSelected[FSelCount++] = ctrl;
   if( FOverlayView ) [(NSView *)FOverlayView setNeedsDisplay:YES];
   [self notifySelChange];
}

- (void)clearSelection
{
   FSelCount = 0; memset( FSelected, 0, sizeof(FSelected) );
   if( FOverlayView ) [(NSView *)FOverlayView setNeedsDisplay:YES];
   [self notifySelChange];
}

- (BOOL)isSelected:(HBControl *)ctrl
{
   for( int i = 0; i < FSelCount; i++ )
      if( FSelected[i] == ctrl ) return YES;
   return NO;
}

- (void)notifySelChange
{
   if( FOnSelChange && HB_IS_BLOCK( FOnSelChange ) ) {
      hb_vmPushEvalSym();
      hb_vmPush( FOnSelChange );
      hb_vmPushNumInt( FSelCount > 0 ? (HB_PTRUINT) FSelected[0] : 0 );
      hb_vmSend( 1 );
   }
}

- (void)windowWillClose:(NSNotification *)notification
{
   FRunning = NO;
   [NSApp stop:nil];
   [NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined
      location:NSZeroPoint modifierFlags:0 timestamp:0
      windowNumber:0 context:nil subtype:0 data1:0 data2:0] atStart:YES];
}

- (BOOL)windowShouldClose:(NSWindow *)sender { return YES; }

@end

/* ======================================================================
 * HB_FUNC Bridge functions
 * ====================================================================== */

/* Object lifetime management */
static NSMutableArray * s_allControls = nil;

static void KeepAlive( HBControl * p )
{
   if( !s_allControls ) s_allControls = [[NSMutableArray alloc] init];
   [s_allControls addObject:p];
}

static HBControl * GetCtrlRaw( int nParam )
{
   return (__bridge HBControl *)(void *)(HB_PTRUINT) hb_parnint( nParam );
}

static void RetCtrl( HBControl * p )
{
   KeepAlive( p );
   hb_retnint( (HB_PTRUINT)(__bridge void *)p );
}

#define GetCtrl(n) GetCtrlRaw(n)
#define GetForm(n) ((HBForm *)GetCtrlRaw(n))

/* --- Form --- */

HB_FUNC( UI_FORMNEW )
{
   HBForm * p = [[HBForm alloc] init];
   if( HB_ISCHAR(1) ) [p setText:hb_parc(1)];
   if( HB_ISNUM(2) )  p->FWidth = hb_parni(2);
   if( HB_ISNUM(3) )  p->FHeight = hb_parni(3);
   if( HB_ISCHAR(4) && HB_ISNUM(5) ) {
      NSString * fontName = [NSString stringWithUTF8String:hb_parc(4)];
      CGFloat fontSize = (CGFloat)hb_parni(5);
      NSFont * font = [NSFont fontWithName:fontName size:fontSize];
      if( !font ) font = [NSFont systemFontOfSize:fontSize];
      p->FFormFont = font; p->FFont = font;
   }
   RetCtrl( p );
}

HB_FUNC( UI_ONSELCHANGE )
{
   HBForm * p = GetForm(1);
   PHB_ITEM pBlock = hb_param(2, HB_IT_BLOCK);
   if( p && pBlock ) {
      if( p->FOnSelChange ) hb_itemRelease( p->FOnSelChange );
      p->FOnSelChange = hb_itemNew( pBlock );
   }
}

HB_FUNC( UI_GETSELECTED )
{
   HBForm * p = GetForm(1);
   if( p && p->FSelCount > 0 )
      hb_retnint( (HB_PTRUINT)(__bridge void *)p->FSelected[0] );
   else hb_retnint( 0 );
}

HB_FUNC( UI_FORMSETDESIGN ) { HBForm * p = GetForm(1); if( p ) [p setDesignMode:hb_parl(2)]; }
HB_FUNC( UI_FORMRUN )       { HBForm * p = GetForm(1); if( p ) [p run]; }
HB_FUNC( UI_FORMSHOW )      { HBForm * p = GetForm(1); if( p ) [p showOnly]; }
HB_FUNC( UI_FORMCLOSE )     { HBForm * p = GetForm(1); if( p ) [p close]; }
HB_FUNC( UI_FORMDESTROY )   { HBForm * p = GetForm(1); if( p ) [s_allControls removeObject:p]; }
HB_FUNC( UI_FORMRESULT )    { HBForm * p = GetForm(1); hb_retni( p ? p->FModalResult : 0 ); }

/* --- Control creation --- */

HB_FUNC( UI_LABELNEW )
{
   HBForm * pForm = GetForm(1); HBLabel * p = [[HBLabel alloc] init];
   if( HB_ISCHAR(2) ) [p setText:hb_parc(2)];
   if( HB_ISNUM(3) ) p->FLeft = hb_parni(3);   if( HB_ISNUM(4) ) p->FTop = hb_parni(4);
   if( HB_ISNUM(5) ) p->FWidth = hb_parni(5);  if( HB_ISNUM(6) ) p->FHeight = hb_parni(6);
   if( pForm ) [pForm addChild:p]; RetCtrl( p );
}

HB_FUNC( UI_EDITNEW )
{
   HBForm * pForm = GetForm(1); HBEdit * p = [[HBEdit alloc] init];
   if( HB_ISCHAR(2) ) [p setText:hb_parc(2)];
   if( HB_ISNUM(3) ) p->FLeft = hb_parni(3);   if( HB_ISNUM(4) ) p->FTop = hb_parni(4);
   if( HB_ISNUM(5) ) p->FWidth = hb_parni(5);  if( HB_ISNUM(6) ) p->FHeight = hb_parni(6);
   if( pForm ) [pForm addChild:p]; RetCtrl( p );
}

HB_FUNC( UI_BUTTONNEW )
{
   HBForm * pForm = GetForm(1); HBButton * p = [[HBButton alloc] init];
   if( HB_ISCHAR(2) ) [p setText:hb_parc(2)];
   if( HB_ISNUM(3) ) p->FLeft = hb_parni(3);   if( HB_ISNUM(4) ) p->FTop = hb_parni(4);
   if( HB_ISNUM(5) ) p->FWidth = hb_parni(5);  if( HB_ISNUM(6) ) p->FHeight = hb_parni(6);
   if( pForm ) [pForm addChild:p]; RetCtrl( p );
}

HB_FUNC( UI_CHECKBOXNEW )
{
   HBForm * pForm = GetForm(1); HBCheckBox * p = [[HBCheckBox alloc] init];
   if( HB_ISCHAR(2) ) [p setText:hb_parc(2)];
   if( HB_ISNUM(3) ) p->FLeft = hb_parni(3);   if( HB_ISNUM(4) ) p->FTop = hb_parni(4);
   if( HB_ISNUM(5) ) p->FWidth = hb_parni(5);  if( HB_ISNUM(6) ) p->FHeight = hb_parni(6);
   if( pForm ) [pForm addChild:p]; RetCtrl( p );
}

HB_FUNC( UI_COMBOBOXNEW )
{
   HBForm * pForm = GetForm(1); HBComboBox * p = [[HBComboBox alloc] init];
   if( HB_ISNUM(2) ) p->FLeft = hb_parni(2);   if( HB_ISNUM(3) ) p->FTop = hb_parni(3);
   if( HB_ISNUM(4) ) p->FWidth = hb_parni(4);  if( HB_ISNUM(5) ) p->FHeight = hb_parni(5);
   if( pForm ) [pForm addChild:p]; RetCtrl( p );
}

HB_FUNC( UI_GROUPBOXNEW )
{
   HBForm * pForm = GetForm(1); HBGroupBox * p = [[HBGroupBox alloc] init];
   if( HB_ISCHAR(2) ) [p setText:hb_parc(2)];
   if( HB_ISNUM(3) ) p->FLeft = hb_parni(3);   if( HB_ISNUM(4) ) p->FTop = hb_parni(4);
   if( HB_ISNUM(5) ) p->FWidth = hb_parni(5);  if( HB_ISNUM(6) ) p->FHeight = hb_parni(6);
   if( pForm ) [pForm addChild:p]; RetCtrl( p );
}

/* --- Property access --- */

HB_FUNC( UI_SETPROP )
{
   HBControl * p = GetCtrl(1);
   const char * szProp = hb_parc(2);
   if( !p || !szProp ) return;

   if( strcasecmp( szProp, "cText" ) == 0 && HB_ISCHAR(3) ) {
      [p setText:hb_parc(3)];
      if( p->FView && [p->FView respondsToSelector:@selector(setStringValue:)] )
         [(id)p->FView setStringValue:[NSString stringWithUTF8String:p->FText]];
      else if( p->FView && [p->FView respondsToSelector:@selector(setTitle:)] )
         [(id)p->FView setTitle:[NSString stringWithUTF8String:p->FText]];
   }
   else if( strcasecmp(szProp,"nLeft")==0 )   { p->FLeft = hb_parni(3); [p updateViewFrame]; }
   else if( strcasecmp(szProp,"nTop")==0 )    { p->FTop = hb_parni(3); [p updateViewFrame]; }
   else if( strcasecmp(szProp,"nWidth")==0 )  { p->FWidth = hb_parni(3); [p updateViewFrame]; }
   else if( strcasecmp(szProp,"nHeight")==0 ) { p->FHeight = hb_parni(3); [p updateViewFrame]; }
   else if( strcasecmp(szProp,"lVisible")==0 ) {
      p->FVisible = hb_parl(3); if( p->FView ) [p->FView setHidden:!p->FVisible]; }
   else if( strcasecmp(szProp,"lEnabled")==0 ) {
      p->FEnabled = hb_parl(3);
      if( p->FView && [p->FView respondsToSelector:@selector(setEnabled:)] )
         [(id)p->FView setEnabled:p->FEnabled]; }
   else if( strcasecmp(szProp,"lDefault")==0 && p->FControlType == CT_BUTTON )
      ((HBButton *)p)->FDefault = hb_parl(3);
   else if( strcasecmp(szProp,"lCancel")==0 && p->FControlType == CT_BUTTON )
      ((HBButton *)p)->FCancel = hb_parl(3);
   else if( strcasecmp(szProp,"lChecked")==0 && p->FControlType == CT_CHECKBOX )
      [(HBCheckBox *)p setChecked:hb_parl(3)];
   else if( strcasecmp(szProp,"cName")==0 && HB_ISCHAR(3) )
      strncpy( p->FName, hb_parc(3), sizeof(p->FName)-1 );
   else if( strcasecmp(szProp,"lSizable")==0 && p->FControlType == CT_FORM )
      ((HBForm *)p)->FSizable = hb_parl(3);
   else if( strcasecmp(szProp,"lAppBar")==0 && p->FControlType == CT_FORM )
      ((HBForm *)p)->FAppBar = hb_parl(3);
   else if( strcasecmp(szProp,"nClrPane")==0 ) {
      p->FClrPane = (unsigned int)hb_parnint(3);
      CGFloat r = (p->FClrPane & 0xFF)/255.0;
      CGFloat g = ((p->FClrPane>>8)&0xFF)/255.0;
      CGFloat b = ((p->FClrPane>>16)&0xFF)/255.0;
      p->FBgColor = [NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0];
      if( p->FControlType == CT_FORM && ((HBForm *)p)->FWindow )
         [((HBForm *)p)->FWindow setBackgroundColor:p->FBgColor];
   }
   else if( strcasecmp(szProp,"oFont")==0 && HB_ISCHAR(3) ) {
      char szFace[64]={0}; int nSize=12;
      const char * val = hb_parc(3);
      const char * comma = strchr(val,',');
      if( comma ) { int len=(int)(comma-val); if(len>63)len=63; memcpy(szFace,val,len); nSize=atoi(comma+1); }
      else strncpy(szFace,val,63);
      if( nSize <= 0 ) nSize = 12;
      NSFont * font = [NSFont fontWithName:[NSString stringWithUTF8String:szFace] size:(CGFloat)nSize];
      if( !font ) font = [NSFont systemFontOfSize:(CGFloat)nSize];
      if( p->FControlType == CT_FORM ) {
         HBForm * pF = (HBForm *)p; pF->FFormFont = font; pF->FFont = font;
         for( int i = 0; i < pF->FChildCount; i++ ) { pF->FChildren[i]->FFont = font; [pF->FChildren[i] applyFont]; }
      } else { p->FFont = font; [p applyFont]; }
   }
}

HB_FUNC( UI_GETPROP )
{
   HBControl * p = GetCtrl(1);
   const char * szProp = hb_parc(2);
   if( !p || !szProp ) { hb_ret(); return; }

   if( strcasecmp(szProp,"cText")==0 )          hb_retc( p->FText );
   else if( strcasecmp(szProp,"nLeft")==0 )      hb_retni( p->FLeft );
   else if( strcasecmp(szProp,"nTop")==0 )       hb_retni( p->FTop );
   else if( strcasecmp(szProp,"nWidth")==0 )     hb_retni( p->FWidth );
   else if( strcasecmp(szProp,"nHeight")==0 )    hb_retni( p->FHeight );
   else if( strcasecmp(szProp,"lDefault")==0 && p->FControlType==CT_BUTTON )
      hb_retl( ((HBButton *)p)->FDefault );
   else if( strcasecmp(szProp,"lCancel")==0 && p->FControlType==CT_BUTTON )
      hb_retl( ((HBButton *)p)->FCancel );
   else if( strcasecmp(szProp,"lChecked")==0 && p->FControlType==CT_CHECKBOX )
      hb_retl( ((HBCheckBox *)p)->FChecked );
   else if( strcasecmp(szProp,"cName")==0 )      hb_retc( p->FName );
   else if( strcasecmp(szProp,"cClassName")==0 ) hb_retc( p->FClassName );
   else if( strcasecmp(szProp,"lSizable")==0 && p->FControlType==CT_FORM )
      hb_retl( ((HBForm *)p)->FSizable );
   else if( strcasecmp(szProp,"lAppBar")==0 && p->FControlType==CT_FORM )
      hb_retl( ((HBForm *)p)->FAppBar );
   else if( strcasecmp(szProp,"nItemIndex")==0 && p->FControlType==CT_COMBOBOX )
      hb_retni( ((HBComboBox *)p)->FItemIndex );
   else if( strcasecmp(szProp,"nClrPane")==0 )   hb_retnint( (HB_MAXINT)p->FClrPane );
   else if( strcasecmp(szProp,"oFont")==0 ) {
      char szFont[128] = "System,12";
      if( p->FFont ) sprintf(szFont,"%s,%d", [[p->FFont fontName] UTF8String], (int)[p->FFont pointSize]);
      hb_retc( szFont );
   }
   else if( strcasecmp(szProp,"cFontName")==0 )
      hb_retc( p->FFont ? [[p->FFont displayName] UTF8String] : "System" );
   else if( strcasecmp(szProp,"nFontSize")==0 )
      hb_retni( p->FFont ? (int)[p->FFont pointSize] : 12 );
   else hb_ret();
}

/* --- Events --- */

HB_FUNC( UI_ONEVENT )
{
   HBControl * p = GetCtrl(1);
   const char * ev = hb_parc(2);
   PHB_ITEM blk = hb_param(3, HB_IT_BLOCK);
   if( p && ev && blk ) [p setEvent:ev block:blk];
}

/* --- ComboBox --- */

HB_FUNC( UI_COMBOADDITEM )
{
   HBComboBox * p = (HBComboBox *)GetCtrl(1);
   if( p && p->FControlType == CT_COMBOBOX && HB_ISCHAR(2) ) [p addItem:hb_parc(2)];
}
HB_FUNC( UI_COMBOSETINDEX )
{
   HBComboBox * p = (HBComboBox *)GetCtrl(1);
   if( p && p->FControlType == CT_COMBOBOX ) [p setItemIndex:hb_parni(2)];
}
HB_FUNC( UI_COMBOGETITEM )
{
   HBComboBox * p = (HBComboBox *)GetCtrl(1); int n = hb_parni(2)-1;
   if( p && p->FControlType == CT_COMBOBOX && n >= 0 && n < p->FItemCount ) hb_retc(p->FItems[n]);
   else hb_retc("");
}
HB_FUNC( UI_COMBOGETCOUNT )
{
   HBComboBox * p = (HBComboBox *)GetCtrl(1);
   hb_retni( p && p->FControlType == CT_COMBOBOX ? p->FItemCount : 0 );
}

/* --- Children --- */

HB_FUNC( UI_GETCHILDCOUNT ) { HBControl * p = GetCtrl(1); hb_retni( p ? p->FChildCount : 0 ); }
HB_FUNC( UI_GETCHILD )
{
   HBControl * p = GetCtrl(1); int n = hb_parni(2)-1;
   if( p && n >= 0 && n < p->FChildCount ) hb_retnint((HB_PTRUINT)(__bridge void *)p->FChildren[n]);
   else hb_retnint(0);
}
HB_FUNC( UI_GETTYPE ) { HBControl * p = GetCtrl(1); hb_retni( p ? p->FControlType : -1 ); }

/* --- Introspection --- */

HB_FUNC( UI_GETPROPCOUNT )
{
   HBControl * p = GetCtrl(1); int n = 0;
   if( p ) { n = 8;
      switch(p->FControlType) { case CT_BUTTON: n+=2; break; case CT_CHECKBOX: n+=1; break;
         case CT_EDIT: n+=2; break; case CT_COMBOBOX: n+=2; break; }
   }
   hb_retni(n);
}

HB_FUNC( UI_GETALLPROPS )
{
   HBControl * p = GetCtrl(1);
   PHB_ITEM pArray, pRow;
   if( !p ) { hb_reta(0); return; }
   pArray = hb_itemArrayNew(0);

   #define ADD_S(n,v,c) pRow=hb_itemArrayNew(4); hb_arraySetC(pRow,1,n); hb_arraySetC(pRow,2,v); \
      hb_arraySetC(pRow,3,c); hb_arraySetC(pRow,4,"S"); hb_arrayAdd(pArray,pRow); hb_itemRelease(pRow);
   #define ADD_N(n,v,c) pRow=hb_itemArrayNew(4); hb_arraySetC(pRow,1,n); hb_arraySetNI(pRow,2,v); \
      hb_arraySetC(pRow,3,c); hb_arraySetC(pRow,4,"N"); hb_arrayAdd(pArray,pRow); hb_itemRelease(pRow);
   #define ADD_L(n,v,c) pRow=hb_itemArrayNew(4); hb_arraySetC(pRow,1,n); hb_arraySetL(pRow,2,v); \
      hb_arraySetC(pRow,3,c); hb_arraySetC(pRow,4,"L"); hb_arrayAdd(pArray,pRow); hb_itemRelease(pRow);
   #define ADD_C(n,v,c) pRow=hb_itemArrayNew(4); hb_arraySetC(pRow,1,n); hb_arraySetNInt(pRow,2,(HB_MAXINT)(v)); \
      hb_arraySetC(pRow,3,c); hb_arraySetC(pRow,4,"C"); hb_arrayAdd(pArray,pRow); hb_itemRelease(pRow);
   #define ADD_F(n,v,c) pRow=hb_itemArrayNew(4); hb_arraySetC(pRow,1,n); hb_arraySetC(pRow,2,v); \
      hb_arraySetC(pRow,3,c); hb_arraySetC(pRow,4,"F"); hb_arrayAdd(pArray,pRow); hb_itemRelease(pRow);

   ADD_S("cClassName",p->FClassName,"Info");
   ADD_S("cName",p->FName,"Appearance");
   ADD_S("cText",p->FText,"Appearance");
   ADD_N("nLeft",p->FLeft,"Position"); ADD_N("nTop",p->FTop,"Position");
   ADD_N("nWidth",p->FWidth,"Position"); ADD_N("nHeight",p->FHeight,"Position");
   ADD_L("lVisible",p->FVisible,"Behavior"); ADD_L("lEnabled",p->FEnabled,"Behavior");
   ADD_L("lTabStop",p->FTabStop,"Behavior");

   { char sf[128]="System,12";
     if(p->FFont) sprintf(sf,"%s,%d",[[p->FFont fontName] UTF8String],(int)[p->FFont pointSize]);
     ADD_F("oFont",sf,"Appearance"); }
   ADD_C("nClrPane",p->FClrPane,"Appearance");

   switch(p->FControlType) {
      case CT_BUTTON:
         ADD_L("lDefault",((HBButton*)p)->FDefault,"Behavior");
         ADD_L("lCancel",((HBButton*)p)->FCancel,"Behavior"); break;
      case CT_CHECKBOX: ADD_L("lChecked",((HBCheckBox*)p)->FChecked,"Data"); break;
      case CT_EDIT:
         ADD_L("lReadOnly",((HBEdit*)p)->FReadOnly,"Behavior");
         ADD_L("lPassword",((HBEdit*)p)->FPassword,"Behavior"); break;
      case CT_COMBOBOX:
         ADD_N("nItemIndex",((HBComboBox*)p)->FItemIndex,"Data");
         ADD_N("nItemCount",((HBComboBox*)p)->FItemCount,"Data"); break;
   }
   hb_itemReturnRelease(pArray);
}

/* --- JSON --- */

HB_FUNC( UI_FORMTOJSON )
{
   HBForm * pForm = GetForm(1);
   char buf[16384], tmp[512]; int pos = 0;
   if( !pForm ) { hb_retc("{}"); return; }
   #define ADDC(s) { int l=(int)strlen(s); if(pos+l<(int)sizeof(buf)-1){strcpy(buf+pos,s);pos+=l;} }
   ADDC("{\"class\":\"Form\"")
   sprintf(tmp,",\"w\":%d,\"h\":%d",pForm->FWidth,pForm->FHeight); ADDC(tmp)
   sprintf(tmp,",\"text\":\"%s\"",pForm->FText); ADDC(tmp)
   ADDC(",\"children\":[")
   for( int i = 0; i < pForm->FChildCount; i++ ) {
      HBControl * p = pForm->FChildren[i];
      if( i > 0 ) ADDC(",")
      ADDC("{")
      sprintf(tmp,"\"type\":%d,\"name\":\"%s\"",p->FControlType,p->FName); ADDC(tmp)
      sprintf(tmp,",\"x\":%d,\"y\":%d,\"w\":%d,\"h\":%d",p->FLeft,p->FTop,p->FWidth,p->FHeight); ADDC(tmp)
      sprintf(tmp,",\"text\":\"%s\"",p->FText); ADDC(tmp)
      if( p->FControlType==CT_BUTTON ) {
         sprintf(tmp,",\"default\":%s,\"cancel\":%s",((HBButton*)p)->FDefault?"true":"false",((HBButton*)p)->FCancel?"true":"false"); ADDC(tmp) }
      if( p->FControlType==CT_CHECKBOX ) {
         sprintf(tmp,",\"checked\":%s",((HBCheckBox*)p)->FChecked?"true":"false"); ADDC(tmp) }
      if( p->FControlType==CT_COMBOBOX ) {
         HBComboBox * cb=(HBComboBox*)p;
         sprintf(tmp,",\"sel\":%d,\"items\":[",cb->FItemIndex); ADDC(tmp)
         for( int j=0; j<cb->FItemCount; j++ ) { if(j>0) ADDC(",") sprintf(tmp,"\"%s\"",cb->FItems[j]); ADDC(tmp) }
         ADDC("]") }
      ADDC("}")
   }
   ADDC("]}") buf[pos]=0;
   hb_retclen(buf,pos);
   #undef ADDC
}

/* ======================================================================
 * Toolbar bridge
 * ====================================================================== */

HB_FUNC( UI_TOOLBARNEW )
{
   HBForm * pForm = GetForm(1);
   HBToolBar * p = [[HBToolBar alloc] init];
   KeepAlive( (HBControl *)p );
   if( pForm ) { pForm->FToolBar = p; p->FCtrlParent = (HBControl *)pForm; }
   hb_retnint( (HB_PTRUINT) p );
}

HB_FUNC( UI_TOOLBTNADD )
{
   HBToolBar * p = (HBToolBar *)(HBControl *)(LONG_PTR)hb_parnint(1);
   if( p && p->FControlType == CT_TOOLBAR )
      hb_retni( [p addButton:hb_parc(2) tooltip:HB_ISCHAR(3)?hb_parc(3):""] );
   else hb_retni( -1 );
}

HB_FUNC( UI_TOOLBTNADDSEP )
{
   HBToolBar * p = (HBToolBar *)(HBControl *)(LONG_PTR)hb_parnint(1);
   if( p && p->FControlType == CT_TOOLBAR ) [p addSeparator];
}

HB_FUNC( UI_TOOLBTNONCLICK )
{
   HBToolBar * p = (HBToolBar *)(HBControl *)(LONG_PTR)hb_parnint(1);
   PHB_ITEM pBlock = hb_param(3, HB_IT_BLOCK);
   if( p && p->FControlType == CT_TOOLBAR && pBlock )
      [p setBtnClick:hb_parni(2) block:pBlock];
}

/* ======================================================================
 * Menu bridge
 * ====================================================================== */

/* Menu storage: use tag-based approach with NSMenu */
static NSMenu * s_currentMenuBar = nil;

HB_FUNC( UI_MENUBARCREATE )
{
   /* On macOS, we use the application menu bar */
   EnsureNSApp();
   NSMenu * menuBar = [[NSMenu alloc] init];
   [NSApp setMainMenu:menuBar];
   s_currentMenuBar = menuBar;
}

HB_FUNC( UI_MENUPOPUPADD )
{
   HBForm * pForm = GetForm(1);
   EnsureNSApp();
   NSMenu * menuBar = [NSApp mainMenu];
   if( !menuBar ) { menuBar = [[NSMenu alloc] init]; [NSApp setMainMenu:menuBar]; }
   NSMenuItem * item = [[NSMenuItem alloc] init];
   NSMenu * popup = [[NSMenu alloc] initWithTitle:[NSString stringWithUTF8String:hb_parc(2)]];
   [item setSubmenu:popup];
   [menuBar addItem:item];
   hb_retnint( (HB_PTRUINT) popup );
}

HB_FUNC( UI_MENUITEMADD ) { hb_retni( -1 ); }  /* Stub - use UI_MENUITEMADDEX */

/* Helper target for menu actions */
@interface HBMenuTarget : NSObject
{ @public PHB_ITEM pAction; }
- (void)menuAction:(id)sender;
@end
@implementation HBMenuTarget
- (void)menuAction:(id)sender {
   if( pAction && HB_IS_BLOCK(pAction) ) {
      hb_vmPushEvalSym(); hb_vmPush(pAction); hb_vmSend(0);
   }
}
@end

static NSMutableArray * s_menuTargets = nil;

HB_FUNC( UI_MENUITEMADDEX )
{
   HBForm * pForm = GetForm(1);
   NSMenu * popup = (NSMenu *)(LONG_PTR)hb_parnint(2);
   PHB_ITEM pBlock = hb_param(4, HB_IT_BLOCK);

   if( !popup || !HB_ISCHAR(3) ) { hb_retni(-1); return; }

   if( !s_menuTargets ) s_menuTargets = [[NSMutableArray alloc] init];

   HBMenuTarget * target = [[HBMenuTarget alloc] init];
   target->pAction = pBlock ? hb_itemNew(pBlock) : NULL;
   [s_menuTargets addObject:target];

   /* Parse accelerator from text (strip &) */
   const char * text = hb_parc(3);
   NSString * title = [NSString stringWithUTF8String:text];
   title = [title stringByReplacingOccurrencesOfString:@"&" withString:@""];

   NSMenuItem * item = [[NSMenuItem alloc] initWithTitle:title
      action:@selector(menuAction:) keyEquivalent:@""];
   [item setTarget:target];
   [popup addItem:item];

   int idx = pForm ? pForm->FMenuItemCount++ : 0;
   if( pForm && pBlock ) pForm->FMenuActions[idx] = hb_itemNew(pBlock);
   hb_retni( idx );
}

HB_FUNC( UI_MENUSEPADD )
{
   NSMenu * popup = (NSMenu *)(LONG_PTR)hb_parnint(2);
   if( popup ) [popup addItem:[NSMenuItem separatorItem]];
}

HB_FUNC( UI_FORMSETSIZABLE )
{
   HBForm * p = GetForm(1);
   if( p ) p->FSizable = hb_parl(2);
}

HB_FUNC( UI_FORMSETAPPBAR )
{
   HBForm * p = GetForm(1);
   if( p ) p->FAppBar = hb_parl(2);
}

HB_FUNC( UI_FORMGETHWND )
{
   /* macOS doesn't use HWND, return the object pointer as handle */
   HBForm * p = GetForm(1);
   hb_retnint( p ? (HB_PTRUINT)(__bridge void *)p : 0 );
}

/* ======================================================================
 * Component Palette (macOS stub - palette created natively)
 * ====================================================================== */

static HBControl * s_palette = NULL;  /* simple storage for palette reference */

HB_FUNC( UI_PALETTENEW )
{
   /* On macOS, palette tabs are part of the window toolbar area */
   /* For now, store as a lightweight placeholder */
   HBControl * p = [[HBControl alloc] init];
   strcpy( p->FClassName, "TComponentPalette" );
   p->FControlType = CT_TOOLBAR + 1;  /* CT_TABCONTROL */
   KeepAlive( p );
   s_palette = p;
   /* Associate with form */
   HBForm * pForm = GetForm(1);
   (void)pForm;
   hb_retnint( (HB_PTRUINT)(__bridge void *)p );
}

HB_FUNC( UI_PALETTEADDTAB )
{
   /* Store tab name for future NSSegmentedControl implementation */
   static int s_tabCount = 0;
   hb_retni( s_tabCount++ );
}

HB_FUNC( UI_PALETTEADDCOMP )
{
   /* Stub - component buttons will be created during window show */
}

HB_FUNC( UI_PALETTEONSELECT )
{
   /* Stub */
}

HB_FUNC( UI_TOOLBARGETWIDTH )
{
   HBToolBar * p = (HBToolBar *)(HBControl *)(LONG_PTR)hb_parnint(1);
   if( p && p->FControlType == CT_TOOLBAR )
      hb_retni( 200 );  /* approximate width for layout */
   else
      hb_retni( 0 );
}

/* ======================================================================
 * StatusBar (macOS)
 * ====================================================================== */

HB_FUNC( UI_STATUSBARCREATE )
{
   /* On macOS, status bar is a thin NSTextField at the bottom of the window */
   /* For now, just mark the form as having a status bar */
   HBForm * p = GetForm(1);
   (void)p;
}

HB_FUNC( UI_STATUSBARSETTEXT )
{
   /* Stub - will be implemented with NSTextField panels */
   HBForm * p = GetForm(1);
   (void)p;
}

HB_FUNC( UI_FORMSELECTCTRL )
{
   HBForm * pForm = GetForm(1);
   HBControl * pCtrl = GetCtrl(2);
   if( pForm && pForm->FDesignMode )
   {
      if( pCtrl && pCtrl != (HBControl *)pForm )
         [pForm selectControl:pCtrl add:NO];
      else
         [pForm clearSelection];
   }
}

HB_FUNC( UI_FORMSETPOS )
{
   HBForm * p = GetForm(1);
   if( p ) {
      p->FLeft = hb_parni(2);
      p->FTop = hb_parni(3);
      p->FCenter = NO;
      if( p->FWindow ) {
         /* macOS uses bottom-left origin, flip Y */
         NSRect screenFrame = [[NSScreen mainScreen] frame];
         NSPoint origin;
         origin.x = p->FLeft;
         origin.y = screenFrame.size.height - p->FTop - p->FHeight;
         [p->FWindow setFrameOrigin:origin];
      }
   }
}

/* --- MsgBox --- */

HB_FUNC( MAC_MSGBOX )
{
   EnsureNSApp();
   NSAlert * alert = [[NSAlert alloc] init];
   [alert setMessageText:[NSString stringWithUTF8String:hb_parc(2) ? hb_parc(2) : ""]];
   [alert setInformativeText:[NSString stringWithUTF8String:hb_parc(1) ? hb_parc(1) : ""]];
   [alert addButtonWithTitle:@"OK"];
   [alert setAlertStyle:NSAlertStyleInformational];
   [alert runModal];
}
