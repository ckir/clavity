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
using Google.Protobuf;

namespace Clavity.Ls.Tests;

// T6 Beat 1: pins the PARTIAL GetCascadeTrajectory proto against the real captured wire
// (TestData/GetCascadeTrajectory.bin, agy 1.0.11). The .bin is the ORACLE — if an assertion fails,
// the proto field numbers are wrong; do NOT edit the golden or weaken the assertion.
public class GetCascadeTrajectoryGoldenTests
{
    private static byte[] Golden(string name) =>
        File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "TestData", name));

    [Fact]
    public void Captured_trajectory_parses_into_partial_proto()
    {
        var resp = GetCascadeTrajectoryResponse.Parser.ParseFrom(Golden("GetCascadeTrajectory.bin"));

        Assert.Equal(18u, resp.NumTotalSteps);
        Assert.NotNull(resp.Trajectory);
        Assert.Equal("f8f914bd-dd32-4b37-9d64-e6473a422b25", resp.Trajectory.CascadeId);
        Assert.Equal(18, resp.Trajectory.Steps.Count);
        Assert.Equal(14, resp.Trajectory.Steps[0].Kind);

        var firstUser = resp.Trajectory.Steps[0].UserInput;
        Assert.NotNull(firstUser);
        Assert.Equal(
            "claudavity: check your inbox and act on any request from claude, then reply on the bus.",
            firstUser.Text);

        // The newest (last) step is an assistant step carrying the conversation's concrete model on its
        // step-metadata (CascadeStep field 5 = CortexStepMetadata). protoc --decode_raw of the golden shows
        // generator_model (11) = 1016 and requested_model (13).model (1) = 1016 on the last step.
        var last = resp.Trajectory.Steps[^1];
        Assert.Equal(15, last.Kind);
        Assert.NotNull(last.Metadata);
        Assert.Equal(1016, last.Metadata.GeneratorModel);
        Assert.Equal(1016, last.Metadata.RequestedModel.Model);

        // The first step is a user-input step (kind 14) — a non-LLM step carries no model (proto3 default 0).
        Assert.Equal(0, resp.Trajectory.Steps[0].Metadata.GeneratorModel);
    }

    [Fact]
    public void Captured_trajectory_pins_step_status_and_tool_calls_and_ITS_turn_end()
    {
        // CascadeStep.status (field 4) and CascadeAssistantOutput.tool_calls (field 7) — added 2026-09-17 so the
        // idle-wait can tell "agy's turn is over" from "agy is mid-turn" when background tasks keep the
        // conversation from going fully idle. protoc --decode_raw of this golden: status is a varint on all 18
        // steps (all 3 = DONE); the kind-15 steps at 3/7/10/14 each carry ONE tool call and the LAST step carries
        // none — this capture's own turn end. Wrong field numbers would read as "no tool calls anywhere", which
        // the tool-calling assertions below reject.
        var resp = GetCascadeTrajectoryResponse.Parser.ParseFrom(Golden("GetCascadeTrajectory.bin"));
        var steps = resp.Trajectory.Steps;

        Assert.All(steps, s => Assert.Equal(3, s.Status));
        foreach (var i in new[] { 3, 7, 10, 14 })
        {
            Assert.Equal(15, steps[i].Kind);
            Assert.Single(steps[i].AssistantOutput.ToolCalls);
        }
        Assert.Empty(steps[^1].AssistantOutput.ToolCalls);

        // The production predicate, run against real captured wire rather than a hand-built step: the golden ends
        // on a turn end, and a prefix of it that stops mid-turn does not.
        Assert.True(AgyView.TurnEnded(resp.Trajectory, before: 0));
        var midTurn = new CascadeTrajectory { CascadeId = resp.Trajectory.CascadeId };
        midTurn.Steps.AddRange(steps.Take(steps.Count - 1)); // ends on the kind-90 step before the final reply
        Assert.False(AgyView.TurnEnded(midTurn, before: 0));
        // ... and the turn end does not count when it is not PAST our own send (before = the index it sits at).
        Assert.False(AgyView.TurnEnded(resp.Trajectory, before: steps.Count - 1));
    }
}
