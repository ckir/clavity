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



using Clavity.Ls;

namespace Clavity.Ls.Tests;

/// <summary>The "a Claude has this agy session" marker. Cross-process behaviour (a held lock blocks ANOTHER process and
/// is released when the holder is killed -9) was measured on Windows and Linux with .clavity/scratch/s65-lock; these rows
/// pin the same contract inside one process, where a second exclusive open conflicts the same way (measured on both).</summary>
public sealed class SessionLockTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "clavity-lock-" + Guid.NewGuid().ToString("N"));
    private string LockPath => Path.Combine(_dir, "sub", "s.lock");

    public void Dispose()
    {
        if (Directory.Exists(_dir))
            Directory.Delete(_dir, recursive: true);
    }

    [Fact]
    public void A_lock_nobody_holds_is_taken_and_a_second_taker_is_refused_until_it_is_released()
    {
        Assert.False(SessionLock.IsTaken(LockPath));            // missing file: not taken
        using (var first = SessionLock.TryTake(LockPath))        // creates the directory and the file
        {
            Assert.NotNull(first);
            Assert.True(SessionLock.IsTaken(LockPath));
            Assert.Null(SessionLock.TryTake(LockPath));
        }
        Assert.False(SessionLock.IsTaken(LockPath));            // released: free again, the file still exists
        Assert.True(File.Exists(LockPath));
        using var again = SessionLock.TryTake(LockPath);
        Assert.NotNull(again);
    }

    [Fact]
    public void Probing_a_free_lock_does_not_take_it()
    {
        using (SessionLock.TryTake(LockPath)) { }               // leave the file behind, unheld
        Assert.False(SessionLock.IsTaken(LockPath));
        using var taken = SessionLock.TryTake(LockPath);         // the probe released its handle
        Assert.NotNull(taken);
    }

    // ---- TryTakeChecked: the folder lock tells "someone holds it" from "cannot lock at all" (section 101) ----

    [Fact]
    public void TryTakeChecked_takes_a_free_lock_and_returns_null_while_another_holder_has_it()
    {
        using (var first = SessionLock.TryTakeChecked(LockPath))
        {
            Assert.NotNull(first);
            Assert.Null(SessionLock.TryTakeChecked(LockPath));   // held: null, NOT an exception
        }
        using var again = SessionLock.TryTakeChecked(LockPath);   // released: free again
        Assert.NotNull(again);
    }

    [Fact]
    public void TryTakeChecked_reports_an_unwritable_directory_instead_of_calling_it_a_holder()
    {
        if (OperatingSystem.IsWindows() || Environment.UserName == "root") return;   // the permission bits are the mechanism
        var locked = Path.Combine(_dir, "ro");
        Directory.CreateDirectory(locked);
        File.SetUnixFileMode(locked, UnixFileMode.UserRead | UnixFileMode.UserExecute);
        try
        {
            Assert.ThrowsAny<Exception>(() => SessionLock.TryTakeChecked(Path.Combine(locked, "x.lock")));
            Assert.IsType<UnauthorizedAccessException>(
                Record.Exception(() => SessionLock.TryTakeChecked(Path.Combine(locked, "x.lock"))));
        }
        finally
        {
            File.SetUnixFileMode(locked, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
        }
    }

    [Fact]
    public void TryTakeChecked_does_not_call_a_lock_it_could_not_even_create_a_holder()
    {
        // An I/O failure that is not contention (here a file name over the 255-byte limit, so no lock file can exist) used to
        // collapse into "another holder has it" and would have printed "already running" for a disk problem.
        if (OperatingSystem.IsWindows()) return;   // long paths are legal there; the mechanism is the Unix name limit
        var tooLong = Path.Combine(_dir, new string('x', 300) + ".lock");
        Assert.Null(SessionLock.TryTake(tooLong));                                   // the old behaviour: a false "held"
        Assert.ThrowsAny<IOException>(() => SessionLock.TryTakeChecked(tooLong));    // the checked one tells the truth
    }
}
