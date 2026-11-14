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



using System.Diagnostics;
using System.Text;
using Clavity.Ls;

namespace Clavity.Ls.Tests;

/// <summary>RUNS the Windows agy-tab script under a real PowerShell (without wt) to prove its finally records agy's end - the
/// file a <c>start</c> waiting for pairing stops on (capstone R1) - under BOTH shells the tab may use (R2: Windows
/// PowerShell 5.1 where pwsh is absent). Windows-only: the script is PowerShell, and CI runs on windows-latest.</summary>
public sealed class WindowsTabScriptRunTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "clavity-wintab-" + Guid.NewGuid().ToString("N"));

    public WindowsTabScriptRunTests() => Directory.CreateDirectory(_dir);

    public void Dispose()
    {
        if (Directory.Exists(_dir))
            Directory.Delete(_dir, recursive: true);
    }

    /// <summary>Runs the decoded tab script with PATH = <paramref name="binDir"/> + the Windows system directory only,
    /// so a real agy installed on the box cannot answer for the fake.</summary>
    private string RunTabScript(string binDir, string shell, string exitedName = "o'x agy-session.exited")
    {
        var exited = Path.Combine(_dir, exitedName);   // default: a quote and a space - both must survive quoting
        var plan = Launcher.Build(new LaunchOptions
        {
            Folder = _dir, SessionId = "sid", AgyLogFilePath = Path.Combine(_dir, "agy.log"),
            AgyEndpointFilePath = Path.Combine(_dir, "ep.json"), AgyExitedFilePath = exited,
        });
        var psi = new ProcessStartInfo(shell)
        {
            ArgumentList = { "-NoProfile", "-NonInteractive", "-EncodedCommand", plan.AgyTab.Arguments[6] },
            UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true,
        };
        psi.Environment["PATH"] = binDir + Path.PathSeparator + Environment.SystemDirectory;
        using var p = Process.Start(psi)!;
        p.StandardOutput.ReadToEnd();
        p.StandardError.ReadToEnd();
        Assert.True(p.WaitForExit(60_000), $"{shell} did not finish within 60 s");
        Assert.True(File.Exists(exited), "the finally did not record agy's end");
        return File.ReadAllText(exited, Encoding.UTF8).Trim();
    }

    [Theory]
    [InlineData("pwsh")]
    [InlineData("powershell")]
    public void Agy_exiting_records_its_exit_code(string shell)
    {
        if (!OperatingSystem.IsWindows())
            return;
        var bin = Directory.CreateDirectory(Path.Combine(_dir, "bin")).FullName;
        File.WriteAllText(Path.Combine(bin, "agy.cmd"), "@exit /b 5\r\n");
        Assert.Equal("5", RunTabScript(bin, shell));
    }

    [Theory]
    [InlineData("pwsh")]
    [InlineData("powershell")]
    public void Agy_missing_still_records_an_end_with_no_code(string shell)
    {
        if (!OperatingSystem.IsWindows())
            return;
        var empty = Directory.CreateDirectory(Path.Combine(_dir, "empty")).FullName;
        Assert.Equal("", RunTabScript(empty, shell));
    }

    [Theory]
    [InlineData("pwsh")]
    [InlineData("powershell")]
    public void An_exited_path_with_wildcard_characters_is_written_literally(string shell)
    {
        // PowerShell reads [ ] * ? in a -Path as a wildcard pattern; the exited path comes from the user profile, which
        // the script does not control. Under -Path, "a[1]" would match a file named "a1" - never this one.
        if (!OperatingSystem.IsWindows())
            return;
        var bin = Directory.CreateDirectory(Path.Combine(_dir, "bin")).FullName;
        File.WriteAllText(Path.Combine(bin, "agy.cmd"), "@exit /b 6\r\n");
        Assert.Equal("6", RunTabScript(bin, shell, exitedName: "a[1] agy-session.exited"));
    }
}
