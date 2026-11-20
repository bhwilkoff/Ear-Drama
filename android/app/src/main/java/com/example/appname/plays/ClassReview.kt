package com.example.appname.plays

// The teacher's review queue on the class page (PLAYS-DESIGN §12.4 Review, §12.11): the seats' chosen takes that no review has
// answered yet, in play order then script order. The rule is `js/class-ui.js` reviewQueue and Apple's `ClassReview`; counts and
// links, never a ranking.

data class ClassReviewItem(val pid: String, val playTitle: String, val take: SharedTake) {
    val id: String get() = take.id
}

object ClassReview {
    /** Takes made by a seat, chosen for their line, with no review. [lineIndex] is the line's place in its script (unknown sorts first). */
    fun queue(productions: List<SharedRecord>, lineIndex: (SharedRecord, String) -> Int): List<ClassReviewItem> =
        productions.flatMap { rec ->
            rec.takes.filter { it.seat != null && rec.chosen[it.lineID] == it.id && rec.reviews[it.id] == null }
                .map { ClassReviewItem(rec.id, rec.title, it) to lineIndex(rec, it.lineID) }
        }.sortedWith(compareBy({ it.first.playTitle }, { it.second })).map { it.first }

    /** "1 take to review", "3 takes to review"; null when nothing waits. */
    fun waiting(count: Int): String? = if (count == 0) null else if (count == 1) "1 take to review" else "$count takes to review"

    /** What goes to the Worker: an empty note is no note. */
    fun note(typed: String): String? = typed.trim().takeIf { it.isNotEmpty() }?.take(500)
}
