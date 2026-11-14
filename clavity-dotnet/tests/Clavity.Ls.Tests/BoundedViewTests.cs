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
using Clavity.Ls;
using Clavity.Ls.Proto;

namespace Clavity.Ls.Tests;

public class BoundedViewTests
{
    private static CascadeTrajectory Traj(string id, params (int kind, string text)[] steps)
    {
        var t = new CascadeTrajectory { CascadeId = id };
        foreach (var (kind, text) in steps)
            t.Steps.Add(new CascadeStep { Kind = kind, UserInput = new CascadeUserInput { Text = text } });
        return t;
    }

    [Fact]
    public void A_trajectory_of_zero_text_steps_is_bounded_by_step_count_not_only_by_chars()
    {
        // A tool step carries no prose, so text is null and cost is 0 -- and `used + 0 > budgetChars` can
        // NEVER be true. The char budget is therefore incapable of bounding a tool-heavy cascade: every one
        // of those steps is emitted regardless of how tight the budget is.
        //
        // BoundedView already knows this failure mode: MaxActivitySteps exists precisely because "the char
        // budget alone does NOT bound a peer that emits a huge COUNT of zero-text steps". But that cap was
        // applied only in ProjectAskReply (the agy_ask path); Summarize (the agy_look path) had none.
        var t = new CascadeTrajectory { CascadeId = "tool-heavy" };
        for (var i = 0; i < BoundedView.MaxActivitySteps + 250; i++)
            t.Steps.Add(new CascadeStep { Kind = 3 });   // no UserInput, no AssistantOutput => null text, 0 cost

        var v = BoundedView.Summarize(t, budgetChars: 900);

        Assert.True(v.Steps.Count <= BoundedView.MaxActivitySteps,
            $"emitted {v.Steps.Count} steps under a 900-char budget -- zero-cost steps are unbounded");
        Assert.True(v.Truncated, "dropping steps must be reported as truncation, not silently");
    }

    [Fact]
    public void Assistant_step_reply_text_is_surfaced_not_just_user_input()
    {
        // Regression: agy's reply (kind 15) carries prose in assistant_output (field 20), NOT user_input (19).
        // BoundedView previously read only user_input, so replies came back null.
        var t = new CascadeTrajectory { CascadeId = "c0" };
        t.Steps.Add(new CascadeStep { Kind = 14, UserInput = new CascadeUserInput { Text = "hi" } });
        t.Steps.Add(new CascadeStep { Kind = 15, AssistantOutput = new CascadeAssistantOutput { Text = "Hello! How can I help?" } });

        var v = BoundedView.Summarize(t);

        Assert.Equal("hi", v.Steps[0].Text);
        Assert.Equal(15, v.Steps[1].Kind);
        Assert.Equal("Hello! How can I help?", v.Steps[1].Text);
    }

    [Fact]
    public void Small_trajectory_is_preserved_untruncated()
    {
        var v = BoundedView.Summarize(Traj("c1", (14, "hello"), (15, "world")));

        Assert.Equal("c1", v.CascadeId);
        Assert.Equal(2, v.TotalSteps);
        Assert.Equal(2, v.Steps.Count);
        Assert.False(v.Truncated);
        Assert.Equal(14, v.Steps[0].Kind);
        Assert.Equal("hello", v.Steps[0].Text);
    }

    [Fact]
    public void Fat_trajectory_trims_within_budget_and_flags_truncated()
    {
        var big = new string('x', 2000);
        var steps = Enumerable.Range(0, 50).Select(_ => (15, big)).ToArray();

        var v = BoundedView.Summarize(Traj("c2", steps), budgetChars: 8000);

        var total = v.Steps.Sum(s => s.Text?.Length ?? 0);
        Assert.True(total <= 8000, $"emitted {total} chars > budget 8000");
        Assert.True(v.Truncated);
        Assert.True(v.Steps.Count < 50);
        Assert.Equal(50, v.TotalSteps);
    }

    [Fact]
    public void Per_step_text_is_truncated_to_cap()
    {
        var v = BoundedView.Summarize(Traj("c3", (14, new string('y', 5000))));

        Assert.NotNull(v.Steps[0].Text);
        Assert.True(v.Steps[0].Text!.Length <= BoundedView.MaxStepTextChars + 1);
    }

    [Fact]
    public void Ask_caps_allow_a_full_long_reply_uncapped_below_the_ask_per_step_limit()
    {
        // A 5000-char reply exceeds the LOOK 1000 cap but is under the ASK 16000 cap → must come back whole.
        var t = new CascadeTrajectory { CascadeId = "c" };
        t.Steps.Add(new CascadeStep { Kind = 15, AssistantOutput = new CascadeAssistantOutput { Text = new string('z', 5000) } });

        var v = BoundedView.Summarize(t, BoundedView.AskBudgetChars, BoundedView.AskMaxStepChars, newestFirst: true);

        Assert.Equal(5000, v.Steps[0].Text!.Length);
        Assert.False(v.Truncated);
    }

    [Fact]
    public void Ask_newestFirst_keeps_the_final_reply_when_budget_is_tight()
    {
        // Older noisy step would overflow the budget in forward order, dropping the real answer.
        // newestFirst must KEEP the final reply and drop the older step instead.
        var t = new CascadeTrajectory { CascadeId = "c" };
        t.Steps.Add(new CascadeStep { Kind = 14, UserInput = new CascadeUserInput { Text = new string('x', 8000) } });
        t.Steps.Add(new CascadeStep { Kind = 15, AssistantOutput = new CascadeAssistantOutput { Text = "THE ANSWER" } });

        var v = BoundedView.Summarize(t, budgetChars: 8000, maxStepChars: 16000, newestFirst: true);

        Assert.Contains(v.Steps, s => s.Text == "THE ANSWER");
        Assert.True(v.Truncated);
    }

    [Fact]
    public void Ask_newestFirst_returns_kept_steps_in_chronological_order()
    {
        var t = new CascadeTrajectory { CascadeId = "c" };
        t.Steps.Add(new CascadeStep { Kind = 14, UserInput = new CascadeUserInput { Text = "first" } });
        t.Steps.Add(new CascadeStep { Kind = 15, AssistantOutput = new CascadeAssistantOutput { Text = "second" } });

        var v = BoundedView.Summarize(t, BoundedView.AskBudgetChars, BoundedView.AskMaxStepChars, newestFirst: true);

        Assert.Equal(2, v.Steps.Count);
        Assert.Equal("first", v.Steps[0].Text);
        Assert.Equal("second", v.Steps[1].Text);
        Assert.False(v.Truncated);
    }

    [Fact]
    public void An_agy_look_step_cut_never_splits_a_surrogate_pair()
    {
        // Capstone R2 FA2: Summarize caps each step at MaxStepTextChars and appends an ellipsis.
        var traj = new CascadeTrajectory { CascadeId = "c" };
        traj.Steps.Add(new CascadeStep
        {
            Kind = 14,
            UserInput = new CascadeUserInput { Text = new string('a', BoundedView.MaxStepTextChars - 1) + "\U0001F600" + "zzz" },
        });
        var view = BoundedView.Summarize(traj);
        Assert.Equal(new string('a', BoundedView.MaxStepTextChars - 1) + "\u2026", view.Steps[0].Text);
    }
}
