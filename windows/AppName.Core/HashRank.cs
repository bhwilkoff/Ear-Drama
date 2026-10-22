namespace AppName.Core;

/// Order-independent deterministic selection (DECISIONS.md 025): any value that must
/// be IDENTICAL across platforms — the daily item, a season key, a rotation — is
/// picked by hashing each candidate's stable id with the period key and taking the
/// max, never by seeding a shuffle. A shuffle depends on iteration order and RNG
/// implementation, which no two stacks share; hash-rank depends only on the id and
/// the key. Every port of this function is pinned by the same golden vectors
/// (HashRankTests mirrors the Swift/Kotlin/JS tests).
///
/// Selection is deterministic; only PRESENTATION may be random. Randomness inside a
/// selection pipeline chooses content once anything downstream truncates.
public static class HashRank
{
    /// FNV-1a 64-bit over the UTF-8 bytes of "{periodKey}|{id}".
    public static ulong Score(string periodKey, string id)
    {
        const ulong offset = 14695981039346656037;
        const ulong prime = 1099511628211;
        var hash = offset;
        foreach (var b in System.Text.Encoding.UTF8.GetBytes(periodKey + "|" + id))
        {
            hash ^= b;
            hash *= prime;
        }
        return hash;
    }

    /// The candidate whose score for this period is highest. Stable under reordering,
    /// insertion, and partial candidate lists — properties a seeded shuffle lacks.
    public static string? Pick(string periodKey, IEnumerable<string> candidateIds)
    {
        string? best = null;
        ulong bestScore = 0;
        foreach (var id in candidateIds)
        {
            var s = Score(periodKey, id);
            if (best is null || s > bestScore || (s == bestScore && string.CompareOrdinal(id, best) > 0))
            {
                best = id;
                bestScore = s;
            }
        }
        return best;
    }
}
