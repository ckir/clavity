// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

using System.Text.RegularExpressions;
using Clavity.Ls;
using Xunit;

namespace Clavity.Ls.Tests;

public class ClientStampTests
{
    [Theory]
    [InlineData("1.0.0+1f601d11db974c9a1e08adbf44464fda4024599c", "1.0.0+1f601d11")]   // the SDK's own shape: 40-char commit cut to 8
    [InlineData("0.11.0+1f601d1", "0.11.0+1f601d1")]                                       // already short: kept, not padded
    [InlineData("0.11.0+12345678", "0.11.0+12345678")]                                     // exactly 8: the boundary, kept whole
    [InlineData("0.11.0+123456789", "0.11.0+12345678")]                                    // 9: the first one that is cut
    [InlineData("0.11.0", "0.11.0")]                                                       // no metadata
    [InlineData("0.11.0+", "0.11.0")]                                                      // empty metadata
    [InlineData("  0.11.0+abc  ", "0.11.0+abc")]
    public void Format_keeps_the_version_and_cuts_the_commit_to_eight_characters(string input, string expected) =>
        Assert.Equal(expected, ClientStamp.Format(input));

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("+abc")]       // metadata with no version names nothing
    public void Format_reports_unknown_when_there_is_no_version_to_name(string? input) =>
        Assert.Equal(ClientStamp.Unknown, ClientStamp.Format(input));

    [Fact]
    public void The_version_verb_prints_the_same_stamp_a_transport_error_names() =>
        Assert.Equal($"clavity-ls {ClientStamp.Value}", CliVerbs.VersionLine());

    [Fact]
    public void This_build_carries_a_real_stamp_not_the_unknown_placeholder()
    {
        // A stamp read from the wrong assembly or attribute degrades to "unknown" or to a bare file version.
        Assert.Matches(new Regex(@"^\d+\.\d+\.\d+(\+[0-9a-f]{1,8})?$"), ClientStamp.Value);
        Assert.NotEqual(ClientStamp.Unknown, ClientStamp.Value);
    }
}
