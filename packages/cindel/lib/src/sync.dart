/// Configuration and adapter contracts for Cindel's local-first sync engine.
///
/// Sync is configured only when opening a database. Cindel does not expose a
/// public command surface for pushing, pulling, pausing, or resuming sync.
final class CindelSyncConfig {
  /// Creates sync configuration for [Cindel.open].
  const CindelSyncConfig({
    required this.adapter,
    this.clientId,
    this.onStatusChanged,
    this.onError,
    this.autoStart = true,
    this.interval = const Duration(seconds: 5),
    this.batchSize = 100,
  });

  /// Backend adapter implemented by the application.
  final CindelSyncAdapter adapter;

  /// Stable client id used for idempotent backend writes.
  ///
  /// When omitted, Cindel persists and reuses an internal id for the database.
  final String? clientId;

  /// Observes status changes. This is informational and does not provide
  /// control over the sync engine.
  final void Function(CindelSyncStatus status)? onStatusChanged;

  /// Observes background sync errors.
  final void Function(Object error, StackTrace stackTrace)? onError;

  /// Starts the internal scheduler after opening the database.
  final bool autoStart;

  /// Background scheduler interval.
  final Duration interval;

  /// Maximum pending mutations sent in one push.
  final int batchSize;
}

/// Backend contract for Cindel Sync.
abstract interface class CindelSyncAdapter {
  /// Pulls remote changes after [CindelPullRequest.checkpoint].
  Future<CindelPullResult> pull(CindelPullRequest request);

  /// Pushes pending local mutations.
  Future<CindelPushResult> push(CindelPushRequest request);
}

/// Current sync status.
final class CindelSyncStatus {
  const CindelSyncStatus({
    required this.phase,
    required this.pendingCount,
    required this.lastSyncAt,
    required this.lastError,
  });

  /// Current phase of the internal sync scheduler.
  final CindelSyncPhase phase;

  /// Number of durable local mutations still waiting for adapter acceptance.
  final int pendingCount;

  /// UTC timestamp of the last completed sync cycle, or `null` before one
  /// succeeds.
  final DateTime? lastSyncAt;

  /// Last background error reported for this status event.
  final Object? lastError;
}

/// High-level sync phase.
enum CindelSyncPhase { idle, syncing, offline, error }

/// Push request sent to the adapter.
final class CindelPushRequest {
  const CindelPushRequest({
    required this.clientId,
    required this.lastPulledCheckpoint,
    required this.schemaVersionByCollection,
    required this.mutations,
  });

  /// Stable client id for this database.
  final String clientId;

  /// Last checkpoint successfully pulled before this push.
  final String? lastPulledCheckpoint;

  /// Registered schema version for each application collection.
  final Map<String, int> schemaVersionByCollection;

  /// Pending local mutations selected from the internal outbox.
  final List<CindelSyncMutation> mutations;
}

/// Push result returned by the adapter.
final class CindelPushResult {
  const CindelPushResult({
    required this.acceptedMutationIds,
    this.rejectedMutations = const [],
    this.correctedChanges = const [],
    this.checkpoint,
  });

  /// Mutation ids the backend has durably accepted.
  final Set<String> acceptedMutationIds;

  /// Mutations the backend will never accept.
  final List<CindelSyncRejectedMutation> rejectedMutations;

  /// Backend truth to apply locally after accepting optimistic mutations.
  final List<CindelRemoteChange> correctedChanges;

  /// Optional checkpoint produced while handling this push.
  final String? checkpoint;
}

/// Pull request sent to the adapter.
final class CindelPullRequest {
  const CindelPullRequest({
    required this.clientId,
    required this.checkpoint,
    required this.schemaVersionByCollection,
    required this.collections,
  });

  /// Stable client id for this database.
  final String clientId;

  /// Last checkpoint applied locally, or `null` for an initial pull.
  final String? checkpoint;

  /// Registered schema version for each application collection.
  final Map<String, int> schemaVersionByCollection;

  /// Application collections this database can apply.
  final Set<String> collections;
}

/// Pull result returned by the adapter.
final class CindelPullResult {
  const CindelPullResult({
    required this.checkpoint,
    required this.changes,
    this.resetRequired = false,
  });

  /// New checkpoint that covers all returned [changes].
  final String checkpoint;

  /// Remote changes after the requested checkpoint.
  final List<CindelRemoteChange> changes;

  /// Whether the backend requires the client to reset before continuing.
  final bool resetRequired;
}

/// Local mutation sent to the backend.
final class CindelSyncMutation {
  const CindelSyncMutation({
    required this.mutationId,
    required this.clientId,
    required this.sequence,
    required this.collection,
    required this.operation,
    this.documentId,
    this.document,
    this.linkName,
    this.targetCollection,
    this.targetIds = const [],
    this.baseCheckpoint,
  });

  /// Stable id used by the backend to deduplicate retries.
  final String mutationId;

  /// Client id that created this mutation.
  final String clientId;

  /// Monotonic local sequence for this client.
  final int sequence;

  /// Application collection affected by this mutation.
  final String collection;

  /// Operation kind.
  final CindelSyncOperation operation;

  /// Document id for document operations.
  final int? documentId;

  /// Canonical document snapshot for upserts.
  final Map<String, Object?>? document;

  /// Link field name for link replacement operations.
  final String? linkName;

  /// Target collection for link replacement operations.
  final String? targetCollection;

  /// Target ids for link replacement operations.
  final List<int> targetIds;

  /// Checkpoint known when the local mutation was recorded.
  final String? baseCheckpoint;
}

/// Supported local mutation operations.
enum CindelSyncOperation { upsert, delete, replaceLinks }

/// Remote change returned by pull or backend corrections.
sealed class CindelRemoteChange {
  const CindelRemoteChange({required this.collection});

  /// Application collection affected by this remote change.
  final String collection;
}

/// Remote document upsert.
final class CindelRemoteUpsert extends CindelRemoteChange {
  const CindelRemoteUpsert({
    required super.collection,
    required this.id,
    required this.document,
  });

  /// Document id to write.
  final int id;

  /// Canonical document snapshot to apply.
  final Map<String, Object?> document;
}

/// Remote document delete.
final class CindelRemoteDelete extends CindelRemoteChange {
  const CindelRemoteDelete({required super.collection, required this.id});

  /// Document id to delete.
  final int id;
}

/// Remote link replacement.
final class CindelRemoteReplaceLinks extends CindelRemoteChange {
  const CindelRemoteReplaceLinks({
    required super.collection,
    required this.id,
    required this.linkName,
    required this.targetCollection,
    required this.targetIds,
  });

  /// Source document id whose link field should be replaced.
  final int id;

  /// Link field name on the source collection.
  final String linkName;

  /// Target collection for linked ids.
  final String targetCollection;

  /// Complete replacement id set for this link.
  final List<int> targetIds;
}

/// Permanently rejected mutation.
final class CindelSyncRejectedMutation {
  const CindelSyncRejectedMutation({
    required this.mutationId,
    required this.reason,
  });

  /// Mutation id that was rejected.
  final String mutationId;

  /// Backend-provided rejection reason.
  final String reason;
}
