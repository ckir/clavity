namespace Clavity.Ls;

/// <summary>
/// The agy pairing instructions (<c>clavity-dotnet/pairing/agy-pairing-INSTALL.md</c>), EMBEDDED in this assembly
/// and written to disk at <c>clavity start</c> so the agy tab's <c>-i "Fetch and follow ..."</c> prompt always has
/// a real file to point at.
/// <para>
/// It used to be looked up next to the exe at <c>plugins/clavity/pairing/</c>, a layout only the Inno installer
/// ever created. Once releases shipped the bare binary, the lookup missed on every install, the launcher dropped
/// the prompt WITHOUT A WORD, and agy never published its endpoint - so <c>agy_ask</c> had nothing to pair with
/// (measured 2026-09-27: both live clavity-launched tabs had no <c>-i</c>). Embedding removes the dependency on
/// how the binary was installed, and rewriting on each start keeps the doc in step with the binary's version.
/// </para>
/// </summary>
public static class PairingDoc
{
    public const string FileName = "agy-pairing-INSTALL.md";

    // Pinned by LogicalName in Clavity.Ls.csproj, so it does not depend on the project's folder layout.
    private const string ResourceName = "Clavity.Ls.agy-pairing-INSTALL.md";

    public static byte[] ReadEmbedded()
    {
        using var stream = typeof(PairingDoc).Assembly.GetManifestResourceStream(ResourceName)
            ?? throw new InvalidOperationException($"embedded resource '{ResourceName}' is missing from {typeof(PairingDoc).Assembly.GetName().Name}");
        using var buffer = new MemoryStream();
        stream.CopyTo(buffer);
        return buffer.ToArray();
    }

    /// <summary>Write the embedded doc to <c>&lt;dir&gt;/agy-pairing-INSTALL.md</c> (creating <paramref name="dir"/>)
    /// and return that path. Skips the write when the file already holds these bytes; otherwise writes a temp file
    /// and moves it into place, so a concurrent <c>clavity start</c> never lets agy read a half-written doc.
    /// IO failures propagate - the caller must not launch agy with a prompt pointing at nothing.</summary>
    public static string Materialize(string dir)
    {
        Directory.CreateDirectory(dir);
        var path = Path.Combine(dir, FileName);
        var content = ReadEmbedded();

        if (File.Exists(path) && File.ReadAllBytes(path).AsSpan().SequenceEqual(content))
            return path;

        var temp = Path.Combine(dir, $"{FileName}.{Guid.NewGuid():N}.tmp");
        try
        {
            File.WriteAllBytes(temp, content);
            File.Move(temp, path, overwrite: true);
        }
        finally
        {
            if (File.Exists(temp))
                File.Delete(temp);
        }
        return path;
    }
}
