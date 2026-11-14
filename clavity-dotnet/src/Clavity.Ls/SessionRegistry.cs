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



namespace Clavity.Ls;

/// <summary>An agy session started by `clavity-ls agy` that `start --attach` without an id may pair with. <see
/// cref="Paired"/>: agy has published an endpoint whose port listens; false while agy is still starting (or waiting on a
/// trust prompt). <see cref="Taken"/>: another `start` holds its lock - returned, not dropped, so the caller can say
/// "already has a Claude" instead of "run agy first". <see cref="Folder"/>: the folder its `.folder` record names.</summary>
public sealed record WaitingSession(string SessionId, bool Paired, DateTime StartedUtc, bool Taken = false, string Folder = "");

/// <summary>Finds the agy sessions in a folder that `start --attach` without an id may pair with (ROADMAP section 65). A
/// session counts when its `.folder` record names the folder, the `clavity-ls agy` running it still holds its `.alive`
/// lock, it has no `.exited` file, and its published endpoint (if any) still listens; a session another `start` holds is
/// returned with <see cref="WaitingSession.Taken"/> set. A null <paramref name="folder"/> returns every folder's sessions
/// (capstone R1: the same folder reached through a symlink does not compare equal, so `start` lists those instead of
/// saying none waits). <paramref name="isHeld"/> answers "does some process hold this lock file?"
/// (<see cref="SessionLock.IsTaken"/>).</summary>
public static class SessionRegistry
{
    private const string Prefix = "agy-session.";
    private const string Suffix = ".folder";

    public static IReadOnlyList<WaitingSession> Find(string userProfileDir, string? folder, IListeningPorts listening,
        Func<string, bool> isHeld)
    {
        var dir = Path.Combine(userProfileDir, ".clavity");
        if (!Directory.Exists(dir))
            return [];
        var found = new List<WaitingSession>();
        foreach (var record in Directory.EnumerateFiles(dir, Prefix + "*" + Suffix))
        {
            var name = Path.GetFileName(record);
            var id = name[Prefix.Length..^Suffix.Length];
            if (!SessionPaths.IsValidSessionId(id))
                continue;
            string recorded;
            try
            {
                recorded = File.ReadAllText(record).Trim();
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                continue;
            }
            if (recorded.Length == 0)
                continue;
            try
            {
                if (folder is not null && !SameFolder(recorded, folder))
                    continue;
            }
            catch (Exception ex) when (ex is ArgumentException or NotSupportedException)
            {
                continue;   // the record's content is not a path (a NUL, say): a malformed record, like an unreadable one
            }
            var paths = SessionPaths.For(userProfileDir, id);
            if (!isHeld(paths.Alive))
                continue;   // its `clavity-ls agy` is gone - killed, or the machine rebooted - even if no .exited exists
            if (File.Exists(paths.Exited))
                continue;
            var paired = false;
            if (AgyEndpoint.TryRead(paths.Endpoint) is { } ep)
            {
                if (!listening.IsListening(ep.Port))
                    continue;   // published, but nothing listens: that agy is gone
                paired = true;
            }
            found.Add(new WaitingSession(id, paired, File.GetLastWriteTimeUtc(record), Taken: isHeld(paths.Lock),
                Folder: recorded));
        }
        return found.OrderBy(s => s.StartedUtc).ThenBy(s => s.SessionId, StringComparer.Ordinal).ToList();
    }

    /// <summary>The comparison `start` and the registry agree on: full paths, a trailing separator ignored, ordinal (the
    /// `agy` verb that writes records runs on Linux / macOS). Symlinks are NOT resolved - on purpose (capstone R1,
    /// AGY-FIRST): a mismatch is answered by listing the sessions waiting elsewhere.</summary>
    public static bool SameFolder(string a, string b) => Normalize(a) == Normalize(b);

    private static string Normalize(string path) => Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));
}
