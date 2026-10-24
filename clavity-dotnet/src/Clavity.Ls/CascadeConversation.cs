// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

namespace Clavity.Ls;

/// <summary>A conversation known to an agy Language Server instance: its id and last-modified time (UTC),
/// from <c>GetAllCascadeTrajectories</c>. <see cref="LastModifiedUtc"/> is null if the LS did not report one.</summary>
public sealed record CascadeConversation(string ConversationId, DateTimeOffset? LastModifiedUtc);
