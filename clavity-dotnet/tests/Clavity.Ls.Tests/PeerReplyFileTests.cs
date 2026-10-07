using System;
using System.IO;
using Clavity.Ls;
using Clavity.Ls.Proto;
using Xunit;

namespace Clavity.Ls.Tests;

public class PeerReplyFileTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "prf-" + Guid.NewGuid().ToString("N"));
    public PeerReplyFileTests() => Directory.CreateDirectory(_root);
    public void Dispose() { if (Directory.Exists(_root)) Directory.Delete(_root, recursive: true); }

    private static Clavity.Ls.Proto.Metadata Md(params string[] uris)
    {
        var md = new Clavity.Ls.Proto.Metadata();
        foreach (var u in uris) md.Workspaces.Add(new Workspace { WorkspaceFolderAbsoluteUri = u });
        return md;
    }

    private void Shield(string content)
    {
        Directory.CreateDirectory(Path.Combine(_root, ".clavity"));
        File.WriteAllText(Path.Combine(_root, ".clavity", ".gitignore"), content);
    }

    [Fact]
    public void One_local_workspace_is_the_root() =>
        Assert.Equal((_root, (string?)null), PeerReplyFile.ResolveRoot(Md(new Uri(_root).AbsoluteUri), null));

    [Fact]
    public void Unknown_none_several_and_non_file_workspaces_request_nothing()
    {
        Assert.Contains("unknown", PeerReplyFile.ResolveRoot(null, "Unimplemented").Status);
        Assert.Contains("no workspace", PeerReplyFile.ResolveRoot(Md(), null).Status);
        Assert.Contains("2 workspaces", PeerReplyFile.ResolveRoot(Md(new Uri(_root).AbsoluteUri, new Uri(_root).AbsoluteUri), null).Status);
        Assert.Contains("not a local folder", PeerReplyFile.ResolveRoot(Md("https://example.com/x"), null).Status);
        Assert.Null(PeerReplyFile.ResolveRoot(null, "x").Root);
    }

    [Fact]
    public void Prepare_requires_a_bare_star_line_in_the_shield()
    {
        Assert.Contains(".gitignore", PeerReplyFile.Prepare(_root, "abc", 7).Status);   // no shield at all
        Shield("*.log\n");
        Assert.Null(PeerReplyFile.Prepare(_root, "abc", 7).Path);                        // a shield without '*'
        Shield("# shield\n*\n");
        var (path, nonce, status) = PeerReplyFile.Prepare(_root, "abc", 7);
        Assert.Null(status);
        Assert.Equal(Path.Combine(_root, ".clavity", "scratch", "agy-replies", "abc-7.md"), path);
        Assert.Matches("^[0-9a-f]{32}$", nonce);
        Assert.True(Directory.Exists(Path.GetDirectoryName(path)));
    }

    [Fact]
    public void The_request_block_ends_on_the_nonce_line_and_names_the_path()
    {
        var block = PeerReplyFile.RequestBlock(@"C:\w\.clavity\scratch\agy-replies\abc-7.md", "0123456789abcdef0123456789abcdef");
        var lines = block.Split('\n');
        Assert.Equal("agy-reply-nonce: 0123456789abcdef0123456789abcdef", lines[^1]);
        Assert.Contains(@"C:\w\.clavity\scratch\agy-replies\abc-7.md", lines);
        Assert.StartsWith("\n\n", block);
    }

    [Fact]
    public void TryRead_returns_the_body_after_a_matching_nonce_line()
    {
        var f = Path.Combine(_root, "r.md");
        File.WriteAllText(f, "agy-reply-nonce: n1\r\n\r\nreport\r\n[VERDICT: ALIGNED]");
        Assert.Equal(("report\n[VERDICT: ALIGNED]", (string?)null), PeerReplyFile.TryRead(f, "n1"));
    }

    [Fact]
    public void TryRead_refuses_absent_wrong_nonce_and_oversized_files()
    {
        var f = Path.Combine(_root, "r.md");
        Assert.Contains("did not write", PeerReplyFile.TryRead(f, "n1").Status);
        File.WriteAllText(f, "agy-reply-nonce: OTHER\n\nreport");
        Assert.Contains("nonce", PeerReplyFile.TryRead(f, "n1").Status);
        File.WriteAllText(f, "agy-reply-nonce: n1\n\n" + new string('x', PeerReplyFile.MaxBytes));
        var big = PeerReplyFile.TryRead(f, "n1");
        Assert.Null(big.Body);
        Assert.Contains("cap", big.Status);
    }

    [Fact]
    public void TryRead_accepts_a_file_of_exactly_MaxBytes_and_refuses_one_byte_more()
    {
        // The cap is inclusive: the oversized row above overshoots by the 21-byte nonce prefix and never probes the edge.
        var f = Path.Combine(_root, "edge.md");
        const string prefix = "agy-reply-nonce: n1\n\n";
        File.WriteAllText(f, prefix + new string('x', PeerReplyFile.MaxBytes - prefix.Length));
        Assert.Equal(PeerReplyFile.MaxBytes, new FileInfo(f).Length);
        var atCap = PeerReplyFile.TryRead(f, "n1");
        Assert.Null(atCap.Status);
        Assert.Equal(PeerReplyFile.MaxBytes - prefix.Length, atCap.Body!.Length);
        File.WriteAllText(f, prefix + new string('x', PeerReplyFile.MaxBytes - prefix.Length + 1));
        Assert.Equal(PeerReplyFile.MaxBytes + 1, new FileInfo(f).Length);
        var over = PeerReplyFile.TryRead(f, "n1");
        Assert.Null(over.Body);
        Assert.Contains("cap", over.Status);
    }
}
