# TMainMenu Component Design

**Date:** 2026-04-24  
**Status:** Approved  

---

## Section 1 — Component and data model

### Component registration

- Constant: `CT_MAINMENU = 132` (added to `hbide.ch`)
- Palette: Standard tab, non-visual area (same row as TTimer)
- Default name: `MainMenu1`
- Syntax in generated form code: `COMPONENT oMainMenu1 TYPE CT_MAINMENU OF Self`

### C struct

```c
#define MAX_MENU_NODES 128

typedef struct {
   char  szCaption[128];
   char  szShortcut[32];
   char  szHandler[128];
   int   bSeparator;
   int   bEnabled;
   int   nParent;   // index into FNodes[], -1 = root-level popup
   int   nLevel;    // 0 = root popup, 1 = item/subpopup, 2 = sub-item, etc.
} HBMenuNode;

typedef struct {
   HBControl   base;
   HBMenuNode  FNodes[MAX_MENU_NODES];
   int         FNodeCount;
} HBMainMenu;
```

### Serialization

`UI_GetProp` / `UI_SetProp` use the property name `aMenuItems`.  
Format: nodes separated by `|`, fields within a node separated by `\t`:

```
Caption\tShortcut\tHandler\tEnabled\tLevel\tParent
```

Separator nodes use an empty Caption and `bSeparator=1`.

---

## Section 2 — Designer UI

The TMainMenu icon appears as a non-visual component below the form canvas (same pattern as TTimer). Double-clicking the icon — or double-clicking the `aMenuItems` row in the generic inspector — opens the **Menu Items Editor** dialog.

The dialog is split into two panes:

**Left pane — hierarchy tree (GtkTreeView, inline-editable Caption):**

```
[+Item] [+SubItem] [+Sep] [↑] [↓] [✕]
─────────────────────────────────────
▼ File
  New       Ctrl+N
  Open      Ctrl+O
  ──────
  Exit      Alt+F4
▼ Edit
  ▶ Find
    Find…   Ctrl+F
    Replace  Ctrl+H
Help
```

**Right pane — properties of selected node:**

| Field    | Widget         |
|----------|----------------|
| Caption  | GtkEntry       |
| Shortcut | GtkEntry       |
| OnClick  | GtkEntry       |
| Enabled  | GtkCheckButton |

Toolbar buttons operate on the selected node:
- **+Item**: adds a sibling item after selection (or root popup if nothing selected)
- **+SubItem**: adds a child under the selected popup
- **+Sep**: adds a separator after selection
- **↑ / ↓**: reorder siblings
- **✕**: delete selected node and its children

Clicking **OK** serializes the tree to `aMenuItems` and calls `UI_SetProp`. Clicking **Cancel** discards changes.

The dialog is triggered by a new property type `'M'` (menu) recognized in `on_row_activated` inside `gtk3_inspector.c`, following the same pattern as the existing `'A'` Array Editor.

At design time the component creates no GTK widgets in the form canvas.

---

## Section 3 — Code generation and parsing

### Generated code (`RegenerateFormCode`)

```harbour
COMPONENT oMainMenu1 TYPE CT_MAINMENU OF Self

DEFINE MENUBAR
   DEFINE POPUP "File"
      MENUITEM "New"  ACTION mnuFileNew()  ACCEL "Ctrl+N"
      MENUITEM "Open" ACTION mnuFileOpen() ACCEL "Ctrl+O"
      MENUSEPARATOR
      MENUITEM "Exit" ACTION mnuFileExit() ACCEL "Alt+F4"
   END POPUP
   DEFINE POPUP "Edit"
      DEFINE POPUP "Find"
         MENUITEM "Find..."   ACTION mnuFindFind()    ACCEL "Ctrl+F"
         MENUITEM "Replace"   ACTION mnuFindReplace() ACCEL "Ctrl+H"
      END POPUP
   END POPUP
END MENUBAR
```

The `DEFINE MENUBAR … END MENUBAR` block is emitted once per TMainMenu component, immediately after its `COMPONENT` line. Nesting depth is derived from `nLevel`.

### Parsing (`RestoreFormFromCode`)

`RestoreFormFromCode` detects the `DEFINE MENUBAR` keyword and enters menu-parse mode. It reads lines until `END MENUBAR`, maintaining a level counter:

- `DEFINE POPUP "X"` → push popup node at current level, increment level
- `END POPUP` → decrement level
- `MENUITEM "X" ACTION y ACCEL "z"` → leaf item node
- `MENUSEPARATOR` → separator node

Each node's `nParent` is the index of the most recent popup at `nLevel - 1`.

---

## Section 4 — Runtime (`HBForm_Run`)

In `HBForm_CreateAllChildren()`, `CT_MAINMENU` nodes are handled separately from visual controls:

```c
case CT_MAINMENU:
   HBMainMenu_Attach( child, form );
   break;
```

`HBMainMenu_Attach` traverses the flat node array and builds the native GTK3 menu bar using the existing infrastructure:

```c
static void HBMainMenu_Attach( HBControl * p, HBForm * form )
{
   HBMainMenu * m = (HBMainMenu *)p;
   GtkWidget  * menubar  = UI_MenuBarCreate( form->FWindow );
   GtkWidget  * popups[8] = {0};   // one slot per nesting level

   for( int i = 0; i < m->FNodeCount; i++ ) {
      HBMenuNode * n = &m->FNodes[i];
      int lv = n->nLevel;

      if( n->bSeparator ) {
         UI_MenuSepAdd( popups[lv] );
      } else if( lv == 0 ) {
         popups[0] = UI_MenuPopupAdd( menubar, n->szCaption );
      } else {
         // determine if this node itself has children (is a sub-popup)
         int hasChildren = ( i + 1 < m->FNodeCount &&
                             m->FNodes[i+1].nLevel > lv );
         if( hasChildren ) {
            popups[lv] = UI_MenuPopupAdd( popups[lv-1], n->szCaption );
         } else {
            UI_MenuItemAddEx( popups[lv-1], n->szCaption,
                              n->szHandler, n->szShortcut, n->bEnabled );
         }
      }
   }
}
```

OnClick handlers are connected inside `UI_MenuItemAddEx` exactly as existing menus do — no changes to the event loop or form-close logic.

TMainMenu does not create any widget at design time; the menu bar is attached only during `HBForm_Run()`.

---

## Section 5 — Testing / success criteria

1. **Design-time drop:** dragging TMainMenu onto the form shows a non-visual icon below the canvas; the component appears in the Object Inspector as `MainMenu1`.
2. **Menu Items Editor:** double-clicking the icon (or `aMenuItems` in the inspector) opens the editor; popups, items, separators, and sub-menus can be added, reordered, and deleted; Caption, Shortcut, OnClick, and Enabled are editable; OK saves, Cancel discards.
3. **Persistence:** saving and reopening the project restores the full menu structure (all nodes, shortcuts, and handlers) without data loss.
4. **Code generation:** `RegenerateFormCode` produces correctly nested `DEFINE MENUBAR / DEFINE POPUP / MENUITEM / MENUSEPARATOR` blocks that compile without errors.
5. **Runtime:** running the project displays a native GTK3 menu bar in the window; clicking an item with a defined handler invokes the corresponding Harbour method; keyboard shortcuts work.
6. **Sub-menus:** a popup nested inside another popup renders as a cascading sub-menu (▶ arrow visible on the parent item).
7. **No regressions:** forms without a TMainMenu component continue to work as before.
