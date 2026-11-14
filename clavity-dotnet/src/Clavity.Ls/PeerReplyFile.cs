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



using Clavity.Ls.Proto;

namespace Clavity.Ls;

/// <summary>ROADMAP section 74 - the SECOND copy of a discipline reply, written by the peer itself (C-request) and read
/// back only when the chat copy fails a [13b] check (C-peer-read). The root is agy's OWN workspace, from the
/// conversation metadata, because agy writes only inside its working directory (agy-assumptions.md, "agy writes only
/// within its own working directory"); exactly one workspace is required, owner-ruled 2026-10-07 (D-root). The file is
/// requested only when that workspace's .clavity/.gitignore already holds a bare '*' line - the server never writes
/// the shield (D-shield). Every failure is a STATUS, never an exception: the peer file must never fail the ask.</summary>
public static class PeerReplyFile
{
    public const string NonceLinePrefix = "agy-reply-nonce: ";

    /// <summary>Largest peer file read back, in bytes - the same cap as the capture (spec panel R3, LI1).</summary>
    public const int MaxBytes = 1024 * 1024;

    public static (string? Root, string? Status) ResolveRoot(Clavity.Ls.Proto.Metadata? metadata, string? metadataError)
    {
        if (metadata is null)
            return (null, $"not requested: agy's workspace is unknown ({ReplyCapture.Clip(metadataError ?? "no metadata", 120)})");
        var n = metadata.Workspaces.Count;
        if (n == 0) return (null, "not requested: agy reported no workspace");
        if (n > 1)
            return (null, $"not requested: agy reported {n} workspaces, and which one it writes into is not measured (ROADMAP section 74, D-root)");
        var uri = metadata.Workspaces[0].WorkspaceFolderAbsoluteUri;
        if (!Uri.TryCreate(uri, UriKind.Absolute, out var u) || !u.IsFile)
            return (null, $"not requested: agy's workspace URI '{ReplyCapture.Clip(uri, 120)}' is not a local folder");
        var root = u.LocalPath;
        if (!Directory.Exists(root))
            return (null, $"not requested: agy's workspace '{ReplyCapture.Clip(root, 120)}' does not exist on this machine");
        return (root, null);
    }

    public static (string? Path, string? Nonce, string? Status) Prepare(string root, string cascadeId, int firstStepIndex)
    {
        try
        {
            if (!ReplyCapture.IsSafeName(cascadeId)) return (null, null, "not requested: the cascade id is not safe in a file name");
            var shield = System.IO.Path.Combine(root, ".clavity", ".gitignore");
            if (!File.Exists(shield) || !File.ReadLines(shield).Any(l => l.Trim() == "*"))
                return (null, null, $"not requested: {shield} does not hold a '*' line, so a reply file there could be committed");
            var dir = System.IO.Path.Combine(root, ".clavity", "scratch", "agy-replies");
            Directory.CreateDirectory(dir);
            return (System.IO.Path.Combine(dir, $"{cascadeId}-{firstStepIndex}.md"), Guid.NewGuid().ToString("N"), null);
        }
        catch (Exception ex)
        {
            return (null, null, "not requested: " + ReplyCapture.OneLine(ex));
        }
    }

    /// <summary>The block appended to a discipline ask. A RECORDED EXCEPTION to the T4b "raw ask only" rule: it is
    /// peer-facing completion protocol, never driver guidance. Its LAST line is the nonce line the file must start with.</summary>
    public static string RequestBlock(string path, string nonce) =>
        "\n\n---\n"
        + "REPLY FILE (completion protocol from the clavity driver, not part of the request above): BEFORE you send your "
        + "final chat message, ALSO write your WHOLE reply, verbatim, to this file - create it, or replace it:\n"
        + path + "\n"
        + "Its FIRST line must be exactly the line below, then a blank line, then the reply. This one write is permitted "
        + "even when the request above is review-only. Then send the same reply in chat as usual.\n"
        + NonceLinePrefix + nonce;

    public static (string? Body, string? Status) TryRead(string path, string nonce)
    {
        try
        {
            if (!File.Exists(path)) return (null, "not read: the peer did not write it");
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            if (!stream.CanSeek) return (null, "not read: not a regular file");
            if (stream.Length > MaxBytes)
                return (null, $"not read: {stream.Length} bytes is over the {MaxBytes}-byte cap; the chat verdict stands");
            using var reader = new StreamReader(stream);
            var text = reader.ReadToEnd().Replace("\r\n", "\n");
            var nl = text.IndexOf('\n');
            var first = nl < 0 ? text : text[..nl];
            if (first.Trim() != NonceLinePrefix + nonce) return (null, "not read: its first line does not carry this ask's nonce");
            var body = nl < 0 ? "" : text[(nl + 1)..];
            if (body.StartsWith('\n')) body = body[1..];
            return (body, null);
        }
        catch (Exception ex)
        {
            return (null, "not read: " + ReplyCapture.OneLine(ex));
        }
    }
}
