# Play Console release-dashboard recommendations read as ONE finding

The Release dashboard's "actions recommended" panel re-analyzes every
release and flags edge-to-edge deprecations, manual bitmap decoding,
resizability restrictions, and similar. Before touching your own code,
DEOBFUSCATE THE ATTRIBUTIONS: on Archive Watch 1.3.434, all four
recommendations (bitmap optimization, both edge-to-edge findings
(`setStatusBarColor` / `setNavigationBarColor` /
`LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES`), and the resizability
detection) traced to ONE transitive library: `androidx.mediarouter`'s
in-app Cast dialogs and their `FetchArtTask`, pulled in by
`play-services-cast-framework`. Nothing flagged was app code (the app
already called `enableEdgeToEdge()`, had no manifest orientation or
resizability restrictions, and hand-decoded no bitmaps, each verified by
grep before changing anything).

**The checklist, in order:**

1. Verify YOUR side is clean first: `enableEdgeToEdge()` in the activity,
   no programmatic `setStatusBarColor`/`setNavigationBarColor`, no
   `screenOrientation`/`resizeableActivity` in any manifest, all image
   loading through Coil.
2. Group the flagged classes by library. Obfuscated short names (`ge2`,
   `qd2`) beside a deobfuscated `androidx.*` frame in the same finding are
   usually the SAME library class through R8.
3. Check whether the library has a real fix. mediarouter did NOT (nothing
   in 1.8.1 or 1.9.0-alpha01). But cast-framework 22.3.0 shipped the
   escape hatch:
   `CastOptions.Builder.setShowSystemOutputSwitcherOnCastIconClick(true)`
   makes the Cast icon open the SYSTEM output switcher on Android 13+
   instead of the flagged mediarouter dialogs. The session still launches
   your custom receiver, so side-loaded subtitles/branding are unaffected;
   pre-13 devices keep the in-app dialog.
4. Ship, and expect honestly: the advisory keys partly on classes PRESENT
   in the dex, and the fallback dialogs remain linked, so Google's own
   library tripping Google's own checker may re-flag on presence alone.
   These are advisories, not violations; when the residue is
   vendor-library-internal with no released fix, say so (and thumbs-down
   the "Is this useful?" prompt) rather than engineering around it.

Related: `docs/store/IAP-TROUBLESHOOTING.md` (the other Play-side
diagnosis doc), Decision 028 (the Cast/GMS flavor split this must never
break; re-run the zero-GMS audit with its negative control after any
cast-framework bump, plus the 16 KB page-size audit since new versions
bring new natives).
