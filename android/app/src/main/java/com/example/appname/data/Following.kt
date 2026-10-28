package com.example.appname.data

/**
 * The followed series a catalog serves, in the order given (newest follow
 * first). A follow this catalog does not serve is kept for sync and not listed.
 */
inline fun resolveFollowing(keys: List<String>, lookup: (String) -> SeriesRow?): List<SeriesRow> =
    keys.mapNotNull(lookup)
