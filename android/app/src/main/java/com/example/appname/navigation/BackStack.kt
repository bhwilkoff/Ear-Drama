package com.example.appname.navigation

import androidx.navigation3.runtime.NavKey

/**
 * ANDROID-DESIGN §3.5: opening a route never stacks a duplicate. A route
 * already on the tab's stack is popped back to (popUpTo, which is singleTop
 * when it is the top), so Detail's series link from a series page returns to
 * that page; a transcript replaces a transcript on top, so the stack holds at
 * most one reading at its end. Every push in AppRoot, the inbox's included,
 * goes through here.
 */
fun MutableList<NavKey>.navigateTo(route: Route) {
    val at = indexOf(route)
    if (at >= 0) {
        while (lastIndex > at) removeAt(lastIndex)
        return
    }
    if (route is Route.Transcript && lastOrNull() is Route.Transcript) removeAt(lastIndex)
    add(route)
}
