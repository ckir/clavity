// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/
// > **This file holds the PolyForm Noncommercial 1.0.0 text followed by the additional terms:
// > an evaluation grant and an anti-circumvention everything in this repo is source-available software. It is not open source.
//
// # PolyForm Noncommercial License 1.0.0
//
// <https://polyformproject.org/licenses/noncommercial/1.0.0>
//
// ## Acceptance
//
// In order to get any license under these terms, you must agree
// to them as both strict obligations and conditions to all
// your licenses.
//
// ## Copyright License
//
// The licensor grants you a copyright license for the
// software to do everything you might do with the software
// that would otherwise infringe the licensor's copyright
// in it for any permitted purpose.  However, you may
// only distribute the software according to [Distribution
// License](#distribution-license) and make changes or new works
// based on the software according to [Changes and New Works
// License](#changes-and-new-works-license).
//
// ## Distribution License
//
// The licensor grants you an additional copyright license
// to distribute copies of the software.  Your license
// to distribute covers distributing the software with
// changes and new works permitted by [Changes and New Works
// License](#changes-and-new-works-license).
//
// ## Notices
//
// You must ensure that anyone who gets a copy of any part of
// the software from you also gets a copy of these terms or the
// URL for them above, as well as copies of any plain-text lines
// beginning with `Required Notice:` that the licensor provided
// with the software.  For example:
//
// > Required Notice: Copyright Yoyodyne, Inc. (http://example.com)
//
// ## Changes and New Works License
//
// The licensor grants you an additional copyright license to
// make changes and new works based on the software for any
// permitted purpose.
//
// ## Patent License
//
// The licensor grants you a patent license for the software that
// covers patent claims the licensor can license, or becomes able
// to license, that you would infringe by using the software.
//
// ## Noncommercial Purposes
//
// Any noncommercial purpose is a permitted purpose.
//
// ## Personal Uses
//
// Personal use for research, experiment, and testing for
// the benefit of public knowledge, personal study, private
// entertainment, hobby projects, amateur pursuits, or religious
// observance, without any anticipated commercial application,
// is use for a permitted purpose.
//
// ## Noncommercial Organizations
//
// Use by any charitable organization, educational institution,
// public research organization, public safety or health
// organization, environmental protection organization,
// or government institution is use for a permitted purpose
// regardless of the source of funding or obligations resulting
// from the funding.
//
// ## Fair Use
//
// You may have "fair use" rights for the software under the
// law. These terms do not limit them.
//
// ## No Other Rights
//
// These terms do not allow you to sublicense or transfer any of
// your licenses to anyone else, or prevent the licensor from
// granting licenses to anyone else.  These terms do not imply
// any other licenses.
//
// ## Patent Defense
//
// If you make any written claim that the software infringes or
// contributes to infringement of any patent, your patent license
// for the software granted under these terms ends immediately. If
// your company makes such a claim, your patent license ends
// immediately for work on behalf of your company.
//
// ## Violations
//
// The first time you are notified in writing that you have
// violated any of these terms, or done anything with the software
// not covered by your licenses, your licenses can nonetheless
// continue if you come into full compliance with these terms,
// and take practical steps to correct past violations, within
// 32 days of receiving notice.  Otherwise, all your licenses
// end immediately.
//
// ## No Liability
//
// ***As far as the law allows, the software comes as is, without
// any warranty or condition, and the licensor will not be liable
// to you for any damages arising out of these terms or the use
// or nature of the software, under any kind of legal claim.***
//
// ## Definitions
//
// The **licensor** is the individual or entity offering these
// terms, and the **software** is the software the licensor makes
// available under these terms.
//
// **You** refers to the individual or entity agreeing to these
// terms.
//
// **Your company** is any legal entity, sole proprietorship,
// or other kind of organization that you work for, plus all
// organizations that have control over, are under the control of,
// or are under common control with that organization.  **Control**
// means ownership of substantially all the assets of an entity,
// or the power to direct its management and policies by vote,
// contract, or otherwise.  Control can be direct or indirect.
//
// **Your licenses** are all the licenses granted to you for the
// software under these terms.
//
// **Use** means anything you do with the software requiring one
// of your licenses.
//
// ---
//
// # ADDITIONAL TERMS (not part of PolyForm Noncommercial 1.0.0)
//
// ## Commercial Evaluation Grant
//
// Any organisation, including one that is not a Noncommercial Organization, may use the software
// for internal testing and evaluation for 30 days from first use, royalty-free. Use beyond that
// period, and any production or other commercial use, requires a paid licence key from the
// licensor.
//
// ## Anti-Circumvention
//
// You may not move, change, disable, or circumvent the licence key functionality in the software,
// and you may not remove or obscure any functionality protected by the licence key or any licence
// notices.




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
            if (await Task.WhenAny(clock.WaitForTimerAsync(pumpBound.Token), task) == task) break;
            time.Advance(pollInterval);
        }
        return await task.WaitAsync(RealBound);
    }

    /// <summary>Advances <paramref name="stall"/> once per window the fake has received, until <paramref name="ask"/> ends, under
    /// <see cref="RealBound"/> and a step cap. For the generation-cap and label tests. It does NOT call
    /// <see cref="AwaitWindowAsync"/>, which throws when the ask ended first; the CALLER awaits <c>ask.WaitAsync(RealBound)</c> and
    /// inspects the reply or the exception. A window whose server answers at once (idle, or its own timeout) arms no timer; the
    /// advance is then harmless.</summary>
    public static async Task PumpWindowsAsync(
        AgyAskIntegrationTests.FakeAskLs fake, Task ask, FakeTimeProvider time, TimeSpan stall, int maxWindows = 200)
    {
        using var cts = new CancellationTokenSource(RealBound);
        var advanced = 0;
        while (!ask.IsCompleted && advanced < maxWindows)
        {
            while (fake.WaitCalls <= advanced && !ask.IsCompleted)
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
