namespace Clavity.Ls;

/// <summary>A conversation known to an agy Language Server instance: its id and last-modified time (UTC),
/// from <c>GetAllCascadeTrajectories</c>. <see cref="LastModifiedUtc"/> is null if the LS did not report one.</summary>
public sealed record CascadeConversation(string ConversationId, DateTimeOffset? LastModifiedUtc);
