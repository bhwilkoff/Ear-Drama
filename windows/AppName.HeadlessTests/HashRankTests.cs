using AppName.Core;

namespace AppName.HeadlessTests;

/// Golden vectors for the deterministic-selection primitive. When Core logic exists
/// on more than one stack, the SAME vectors must pass on every stack (Swift, Kotlin,
/// JS, C#) — byte-compatibility is what lets a Windows player see the same daily
/// item as a phone/web player. If these values change, every mirror must change in
/// the same commit.
public class HashRankTests
{
    [Fact]
    public void Fnv1a_matches_golden_vectors()
    {
        // FNV-1a 64 of "2026-01-01|alpha" etc. — pinned, not derived in the test.
        Assert.Equal(4483385605563506243UL, HashRank.Score("2026-01-01", "alpha"));
        Assert.Equal(14720152719078737679UL, HashRank.Score("2026-01-01", "beta"));
        Assert.Equal(17243270460336070UL, HashRank.Score("2026-01-02", "alpha"));
    }

    [Fact]
    public void Pick_is_order_independent()
    {
        var ids = new[] { "alpha", "beta", "gamma", "delta" };
        var forward = HashRank.Pick("2026-01-01", ids);
        var reversed = HashRank.Pick("2026-01-01", ids.Reverse());
        Assert.Equal(forward, reversed);
        Assert.NotNull(forward);
    }

    [Fact]
    public void Pick_changes_with_the_period()
    {
        var ids = Enumerable.Range(0, 50).Select(i => $"item-{i}").ToArray();
        var days = Enumerable.Range(1, 20).Select(d => $"2026-01-{d:D2}");
        var picks = days.Select(day => HashRank.Pick(day, ids)).Distinct().Count();
        Assert.True(picks > 1, "20 periods picked the same item — the period key is not mixing");
    }
}
