// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/




using Microsoft.Extensions.Time.Testing;

namespace Clavity.Integration.Tests;

/// <summary>Shared plumbing for the tests that drive <c>AgyViewOptions.TimeProvider</c> with a <see cref="FakeTimeProvider"/>
/// (ROADMAP sections 106 and 113). Every await on the virtual-clock path is bounded in REAL time by <see cref="RealBound"/>: a
/// mutant that leaves a real timer or a real clock read in AgyView then fails by that bound instead of hanging or passing slowly.</summary>
internal static class VirtualClock
{
    // ROADMAP section 106: tests that drive AgyViewOptions.TimeProvider with a FakeTimeProvider still wait on REAL RPC round
    // trips, so every await is bounded by a real-time limit. A mutant that leaves a real timer in place then fails by this bound
    // instead of passing slowly (a 10-minute window cannot finish inside it).
    public static readonly TimeSpan RealBound = TimeSpan.FromSeconds(30);

    /// <summary>Wait until the fake has received wait call number <paramref name="window"/>. The fake counts a call AFTER the client
    /// armed that window's timer (the handler increments on entry), so a virtual-clock advance made after this returns always
    /// lands on an armed timer. Fails fast, with the ask's own exception, when the ask ends before the window is reached, and
    /// otherwise ends in OperationCanceledException at <see cref="RealBound"/>.</summary>
    public static async Task AwaitWindowAsync(AgyAskIntegrationTests.FakeAskLs fake, Task ask, int window)
    {
        using var cts = new CancellationTokenSource(RealBound);
        while (fake.WaitCalls < window)
        {
            if (ask.IsCompleted)
            {
                await ask;   // rethrows ITS exception when it faulted
                throw new InvalidOperationException($"the ask finished before wait window {window} was reached");
            }
            await Task.Delay(5, cts.Token);
        }
    }

    /// <summary>A virtual clock that starts FIVE MINUTES BEFORE the real now (see AgyChannelDownTests, section 106): a stray
    /// real-clock read can then neither look "past" a fake deadline nor agree with it. EVERY test added or converted by section
    /// 113 uses it: with a fake that starts at the real now, <c>generating = (total, DateTime.UtcNow)</c> reads the same instant
    /// as the virtual clock and the mutant stays green. The fake deadline stays in the real future (real now + 5 min), so the real
    /// clock never reaches it inside a test's bound.</summary>
    public static (FakeTimeProvider Time, TimerCountingTimeProvider Clock) NewClock()
    {
        var time = new FakeTimeProvider(DateTimeOffset.UtcNow - TimeSpan.FromMinutes(5));
        return (time, new TimerCountingTimeProvider(time));
    }

    /// <summary>Starts <paramref name="call"/>, then advances ONE poll interval per armed timer (a poll-delay timer exists before
    /// the signal, so the advance lands on it), under <see cref="RealBound"/> and a step cap, and returns the call's result. A call
    /// that ends before any timer is armed returns at once. The boot-race verdict is only issued at the deadline by design, so a
    /// single advance of the whole budget would end the test right after poll 1; one interval per armed timer exercises every poll.</summary>
    public static async Task<T> PumpBootRaceAsync<T>(
        Func<Task<T>> call, FakeTimeProvider time, TimerCountingTimeProvider clock, TimeSpan pollInterval, int maxSteps = 50)
    {
        var task = call();
        using var pumpBound = new CancellationTokenSource(RealBound);
        for (var step = 0; step < maxSteps && !task.IsCompleted; step++)   // the cap: a runaway loop fails, it never spins
        {
            var winner = await Task.WhenAny(clock.WaitForTimerAsync(pumpBound.Token), task);
            if (winner == task) break;
            await winner;   // a timer wait that expired at RealBound throws here; without it the loop fell through to up to 49 more advances and the deadline arrived (test audit G2)
            time.Advance(pollInterval);
        }
        return await task.WaitAsync(RealBound);
    }

    /// <summary>Advances <paramref name="stall"/> once per window that is PARKED on the server (<c>FakeAskLs.BlockedWindows</c>), until
    /// <paramref name="ask"/> ends, under <see cref="RealBound"/> and a step cap. For the generation-cap and label tests. It does NOT
    /// call <see cref="AwaitWindowAsync"/>, which throws when the ask ended first; the CALLER awaits <c>ask.WaitAsync(RealBound)</c> and
    /// inspects the reply or the exception. It gates on the parked count and NOT on <c>WaitCalls</c> on purpose: AgyView arms a window
    /// timer for EVERY window, so an advance onto a window whose server answers at once (idle, or its own timeout) can fire that timer
    /// before the client reads the reply, and the client then runs an extra window (measured: WaitCalls 26 to 28 against a plan of
    /// 25). A parked window's handler is running, so the client armed its timer first and the advance lands on it.</summary>
    public static async Task PumpWindowsAsync(
        AgyAskIntegrationTests.FakeAskLs fake, Task ask, FakeTimeProvider time, TimeSpan stall, int maxWindows = 200)
    {
        using var cts = new CancellationTokenSource(RealBound);
        var advanced = 0;
        while (!ask.IsCompleted && advanced < maxWindows)
        {
            while (fake.BlockedWindows <= advanced && !ask.IsCompleted)
                await Task.Delay(5, cts.Token);
            if (ask.IsCompleted) break;
            time.Advance(stall);
            advanced++;
        }
    }
}

/// <summary>A FakeTimeProvider wrapper that tells the test every time AgyView ARMS a timer (each <c>Task.Delay</c> creates one). The
/// boot-race loop re-arms its poll delay once per poll, so waiting for a new timer is how the test knows the loop is parked
/// and a virtual-clock advance will land on it - no sleeping, no guessing (ROADMAP section 106).</summary>
internal sealed class TimerCountingTimeProvider : TimeProvider
{
    private readonly FakeTimeProvider _inner;
    private readonly SemaphoreSlim _armed = new(0);
    private int _timersCreated;

    public TimerCountingTimeProvider(FakeTimeProvider inner) => _inner = inner;

    public int TimersCreated => Volatile.Read(ref _timersCreated);
    public Task WaitForTimerAsync(CancellationToken cancellationToken) => _armed.WaitAsync(cancellationToken);

    public override DateTimeOffset GetUtcNow() => _inner.GetUtcNow();
    public override long GetTimestamp() => _inner.GetTimestamp();
    public override long TimestampFrequency => _inner.TimestampFrequency;
    public override TimeZoneInfo LocalTimeZone => _inner.LocalTimeZone;

    public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
    {
        var timer = _inner.CreateTimer(callback, state, dueTime, period);   // exists BEFORE the signal, so an advance after it fires it
        Interlocked.Increment(ref _timersCreated);
        _armed.Release();
        return timer;
    }
}
