# [APP NAME] iPad Design (BINDING)

<!-- SEED TEMPLATE. Author as docs/IPAD-DESIGN.md once the iPad build
     is more than the iPhone layout at a larger size, or as soon as a
     screenshot at 1366 pt shows a button or a line of text no designer
     would choose. It EXTENDS docs/iOS-DESIGN.md (seed:
     IOS-DESIGN-template.md); it never replaces it. Read
     `ios-production-gotchas` (size-class adaptivity) and
     `macos-platform-patterns` (the menu bar, pointer and window rules
     the iPad now shares) first.

     The numbers and rules below are iPadOS facts from Archive Watch's
     IPAD-DESIGN.md, measured on an iPad Pro 12.9-inch. Keep them unless
     your own measurements say otherwise; replace every [BRACKET];
     delete these comments as you go. -->

**Binding.** Every surface the iPad shows at regular width must trace
to a rule here or in `docs/iOS-DESIGN.md`. Where the two could be read
as disagreeing, iOS-DESIGN wins on shell and taxonomy; this document
wins on composition and measure at regular width.

I want the iPad to be its own first-class experience, not the phone
blown up.

The failure this document prevents is not ugliness. Archive Watch's
first iPad build looked clean and had zero clipped text. But a layout
designed for 390 points, stretched to 1366, drew a Play button over a
thousand points wide and a synopsis at 115 characters a line. Nothing
was broken, and nothing was designed.

The cost of this document: a second set of rules to keep in step with
iOS-DESIGN, and a real iPad for every check. The simulator rotates
freely and is a fine second rig; the measurements below came from the
device.

---

## §1. Principles

1.1 **The iPad is a different composition of the same parts, not a
different app.** One shell, one destination registry, one data plane.
What changes at regular width is how much sits side by side and how
wide a line may get, never which features exist.

1.2 **Adaptivity is by size class, never by device.**
`@Environment(\.horizontalSizeClass)`, never
`UIDevice.current.userInterfaceIdiom`. That is what makes an iPhone in
landscape, an iPad in Split View and a resized window all correct for
free, and why these are really regular-width rules.

1.3 **Density comes from more content, not bigger content.** A wide
screen earns more items per row and more rows in view, never larger
versions of the same items.

1.4 **A control's width is a claim about its importance.** A button
that spans a 12.9-inch screen claims to be the most important thing in
the app. Primary actions get a deliberate size at regular width, not
the whole window.

---

## §2. Measure (the core rule)

2.1 **Prose is capped at 700 pt** at regular width, leading-aligned in
its column: synopsis, reviews, footers, the body of a settings section.
Any run of prose, not only the one you expected to be widest. At 700 pt
`.body` lands near 65 characters a line, inside the 45 to 75 range.
Below that width nothing changes, so the iPhone is untouched.

2.2 **A primary action is capped at 480 pt** at regular width,
leading-aligned with its content, never `maxWidth: .infinity` across
the window.

2.3 **A scope selector (segmented picker) is capped at 560 pt** at
regular width, leading-aligned. On compact width it stays full width.

2.4 **The cap is on the content, not the screen.** The space beside
capped content is deliberate, not an error to fill. Where a surface has
a natural second column (§3), use it instead.

---

## §3. Composition at regular width

3.1 **Detail is two columns:** artwork leading; identity, actions and
prose trailing, with the prose sharing the column's edge with the
controls above it. One view with a size-class branch; never a second
Detail implementation.

3.2 **Rows keep their horizontal scroll** and show more members per
screen. More faces visible, not bigger faces.

3.3 **Grids use `LazyVGrid(.adaptive(minimum:))`**, which yields
[N] columns at 1366 pt and [n] on a phone from one declaration. Never
a fixed column count.

3.4 **Both orientations are first class,** and no layout keys on
orientation directly. A rule keyed to `isLandscape` breaks in Split
View and Stage Manager.

---

## §4. Sheets and inspectors

4.1 **Detents do not apply on iPad.** A `.sheet` is a centred form
sheet whatever its content, so a short state leaves empty space. Do
not fix that with `.presentationSizing(.fitted)` (it collapsed one
sheet to about 140 pt wide) or `.form.fitted(horizontal: false,
vertical: true)` (it clipped the content to a strip). Empty space below
short content is acceptable; if it must look deliberate, change the
content.

4.2 **Controls that adjust something still on screen are an inspector,
not a sheet.** `.inspector(isPresented:)` gives a trailing column at
regular width, so the thing being adjusted stays visible and live, and
the same content presents as a sheet on compact width. One modifier,
no size-class branch. Give the column a width that fits its longest
line ([e.g. 320 to 440 pt]) and keep the content beside it out from
under it.

---

## §5. The sidebar holds places

5.1 **One `TabView(.sidebarAdaptable)`.** The sidebar lists every place
a person goes (the Music and TV apps are the model); the tab bar keeps
the phone's [N] tabs. Sidebar-only entries carry
`.defaultVisibility(.hidden, for: .tabBar)`.

5.2 **The sidebar's sections:** [Home · Browse (scope A, scope B) ·
Search · Library (place A, place B) · …]. A scope that is a sidebar
entry opens with no segmented control above it.

5.3 **The sidebar is customizable** (`TabViewCustomization`,
persisted). The tab-bar tabs cannot be hidden.

5.4 **Settings is not a sidebar place.** It is the app menu's
Settings… (⌘,) and [the Home gear], one sheet.

---

## §6. The pointer and the context menu

6.1 **Everything tappable answers the pointer.** Tiles lift
(`.hoverEffect(.lift)`); an element too small for its words names
itself on hover (`.help`). `hoverEffect` is inert on touch.

6.2 **Every item has a context menu:** right-click with a pointer, long
press on touch, on iPhone too. It is the Mac card's menu, not a new
set: [Open in New Window (where windows exist), Favorite, Share].

---

## §7. Drag and drop

7.1 **An item can be picked up.** Tiles are `.draggable` at regular
width. The payload is the item's public web link, so it lands in Notes
or Mail as something a person can open.

7.2 **Where it can be put down:** [a playlist row adds it; the
Favorites sidebar entry favorites it]. A dropped link to an item we
know counts the same as a dragged tile. Any other drop is refused,
never guessed.

---

## §8. The menu bar and the keyboard

8.1 **The iPad shows the Mac's menus in the Mac's words.** The same
`.commands` build both menu bars. Name every command exactly as
`MenuCommands_macOS.swift` does, so a person who uses both reads one
vocabulary: [Go (places ⌘1 to ⌘N, Search ⌘F, Back ⌘[) · Item (Play,
Favorite, Copy Link) · Help].

8.2 **A command for the item in front is published per window**
(`focusedSceneValue`). With nothing in front it is dimmed, never
hidden.

8.3 **A sheet's cancel key is ⌘.** (`.cancelAction`), and its default
key is Return when it has one confirming action. Esc is not the iPad's
cancel key.

8.4 **The player's keys belong to the player.** `AVPlayerViewController`
already answers Space and the arrows; add no competing menu.

8.5 **The menu bar needs Windowed Apps** (Settings > Multitasking). In
full-screen apps iPadOS draws none, so every command must also work by
its key alone.

---

## §9. Windows

9.1 **An item can open in its own window** (Open in New Window, offered
only where `supportsMultipleWindows` is true). The window's title is the
item's title.

9.2 **Every window owns its navigation.** The `Router` is per scene,
never an app-level singleton; two windows sharing one move each other's
stacks. The data store, account and persistence container stay
app-wide.

9.3 **Scenes are declared for iPad only**
(`UIApplicationSceneManifest~ipad`), so iPhone and tvOS read no change.

9.4 **A new window opens as the one it came from does.** From a
full-screen window the new one is full screen and `defaultSize` is
ignored. That is the system's rule, not ours to override.

---

## §10. What the iPad does not do

<!-- List what is deliberately absent on iPad, each with the owner's
     dated words and a PARITY.md 🚫 cell. A missing feature with no
     row here will be "fixed" by the next session. -->

| Not on iPad | Why | Owner, date | PARITY row |
|---|---|---|---|
| [e.g. the Mac-only pro editor] | | | |

---

## §11. Anti-patterns (never)

11.1 `frame(maxWidth: .infinity)` on prose or a primary button without a
companion cap at regular width.
11.2 A parallel iPad view (`DetailView_iPad`). One view, size-class
branches inside it.
11.3 `UIDevice.current.userInterfaceIdiom`.
11.4 Filling space because it exists. A decorative panel beside capped
content is decoration.
11.5 A sizing modifier, fixed frame or spacer on an iPad sheet (§4.1).

---

## §12. The tests (run before any iPad surface ships)

12.1 **The measure test.** Screenshot at 1366 pt; count characters on
the longest line of prose on screen. Over about 80 fails §2.1.

12.2 **The claim test.** Is any control wider than 480 pt? If so, is it
really the most important thing on screen?

12.3 **The both-orientations test.** Rotate the device in the test run,
rather than trusting that it would pass.

12.4 **The compact-unchanged test.** After any iPad change, the iPhone
suite stays green on a real iPhone.

12.5 **Prove geometry, not presence.** A SwiftUI image with no
accessibility label is not exposed to XCUITest; assert the title's
x-position instead (stacked, it starts at the margin; two-column, it
starts far to the right). Take one snapshot with
`allElementsBoundByIndex`, never `element(boundBy:)` in a loop.

Bring back a 1366 pt screenshot of every surface you touched.
