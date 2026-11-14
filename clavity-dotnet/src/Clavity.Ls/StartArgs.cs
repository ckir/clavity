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

/// <summary>Parsed <c>clavity-ls start [folder] [--attach [&lt;session-id&gt;]] [--profile &lt;name&gt;] [claude-args...]</c>
/// (<c>--attach</c> and <c>--profile</c> in either order).</summary>
public sealed record StartArgs(string Folder, bool Attach, string? AttachSessionId, string? Profile, string[] ClaudeArgs)
{
    public const string AttachFlag = "--attach";
    public const string ProfileFlag = "--profile";

    /// <summary>The folder is the first argument unless it starts with '-'. <c>--attach</c> and <c>--profile</c> are ours
    /// only in the run of arguments DIRECTLY after it (or first, with no folder), in either order, so every later
    /// argument still reaches Claude untouched. <c>--profile</c> takes a required value (non-blank, not starting with
    /// '-') and may appear once; a missing or bad value or a repeat throws <see cref="ArgumentException"/>. The
    /// <c>--attach</c> id is optional (ROADMAP
    /// section 65: with none, `start` pairs with the one agy session waiting in the folder): a valid id is consumed; an
    /// argument SHAPED like an id but invalid throws <see cref="ArgumentException"/> (a mistyped id must not silently
    /// become a prompt); anything else is Claude's. Only a valid id ever becomes part of a file name.</summary>
    public static StartArgs Parse(string[] rest, string currentDirectory)
    {
        var i = 0;
        string folder;
        if (rest.Length > 0 && !rest[0].StartsWith('-'))
        {
            folder = Path.GetFullPath(rest[0], currentDirectory);
            i = 1;
        }
        else
        {
            folder = currentDirectory;
        }

        var attach = false;
        string? id = null;
        string? profile = null;
        while (i < rest.Length)
        {
            if (rest[i] == AttachFlag && !attach)
            {
                attach = true;
                i++;
                if (i < rest.Length && SessionPaths.IsValidSessionId(rest[i]))
                {
                    id = rest[i];
                    i++;
                }
                else if (i < rest.Length && LooksLikeAnId(rest[i]))
                {
                    throw new ArgumentException(
                        $"{AttachFlag} '{rest[i]}' is not a session id - use the one `clavity-ls agy` printed, or none.");
                }
            }
            else if (rest[i] == ProfileFlag)
            {
                if (profile is not null)
                {
                    throw new ArgumentException($"{ProfileFlag} may be given only once.");
                }

                i++;
                if (i >= rest.Length || string.IsNullOrWhiteSpace(rest[i]) || rest[i].StartsWith('-'))
                {
                    throw new ArgumentException($"{ProfileFlag} needs a profile name (a non-blank value not starting with '-').");
                }

                if (!ValidProfileName(rest[i]))
                {
                    throw new ArgumentException(
                        $"{ProfileFlag} '{rest[i]}' is not a valid profile name - use only letters, digits, '.', '_' and '-' (not '.' or '..').");
                }

                profile = rest[i];
                i++;
            }
            else
            {
                break;
            }
        }

        return new StartArgs(folder, attach, id, profile, rest[i..]);
    }

    // A profile name becomes a file name (the setup lock) and a directory name (agent-profile), so only a plain token is allowed:
    // no path separators, drive colons, spaces or other characters a path or a shell would treat specially.
    private static bool ValidProfileName(string s) =>
        s is not ("." or "..") && s.Length > 0 && s.All(c => char.IsAsciiLetterOrDigit(c) || c is '.' or '_' or '-');

    // Hex digits and dashes only, 8 or more: what a mistyped or truncated session id looks like.
    private static bool LooksLikeAnId(string s) => s.Length >= 8 && s.All(c => c == '-' || char.IsAsciiHexDigit(c));
}
