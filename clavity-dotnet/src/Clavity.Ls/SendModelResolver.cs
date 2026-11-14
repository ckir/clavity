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



using System.Linq;
using Clavity.Ls.Proto;

namespace Clavity.Ls;

/// <summary>Where a resolved send-model id came from (surfaced to the operator on stderr).</summary>
public enum ModelSource { Trajectory, Default, Legacy }

/// <summary>
/// Pure resolution of the concrete agy send-model id, so an agy model-renumber can't silently break the live
/// write. The orchestration (RPC calls, legacy fallback, stderr surface) lives in <see cref="AgyView"/>; these
/// functions are side-effect-free and unit-tested without a server.
/// </summary>
public static class SendModelResolver
{
    /// <summary>
    /// Walk the trajectory steps NEWEST-FIRST and return the first concrete (non-zero) model id. Steps are
    /// appended oldest-first (the repeated field preserves append order; <c>AgyView.AskAsync</c> reads new
    /// replies via <c>Steps.Skip(before)</c>), so newest-first = iterate from the end. Within a step, prefer
    /// <c>generator_model</c> (always a resolved concrete int) over <c>requested_model.model</c> (0 for an
    /// alias-driven step). Returns null when no step bears a model — a brand-new conversation.
    /// </summary>
    public static int? ResolveFromTrajectory(CascadeTrajectory trajectory)
    {
        for (var i = trajectory.Steps.Count - 1; i >= 0; i--)
        {
            var meta = trajectory.Steps[i].Metadata;
            if (meta is null) continue;                       // step omitted field 5 entirely (defensive).
            if (meta.GeneratorModel != 0) return meta.GeneratorModel;
            var requested = meta.RequestedModel?.Model ?? 0;  // oneof unset -> 0.
            if (requested != 0) return requested;
        }
        return null;
    }

    /// <summary>
    /// agy's default model: <c>default_agent_model_id</c> (a key) → the <c>models</c> map → its concrete model
    /// int. Null when the catalog has no default key, the entry is missing, or its model is 0.
    /// </summary>
    public static int? ResolveDefault(FetchAvailableModelsResponse catalog)
    {
        if (catalog is null || string.IsNullOrEmpty(catalog.DefaultAgentModelId))
            return null;
        return catalog.Models.TryGetValue(catalog.DefaultAgentModelId, out var details) && details.Model != 0
            ? details.Model
            : null;
    }

    /// <summary>True if <paramref name="model"/> is a current id in the live catalog (any entry's model int).</summary>
    public static bool IsInCatalog(int model, FetchAvailableModelsResponse catalog) =>
        catalog is not null && catalog.Models.Values.Any(d => d.Model == model);
}
