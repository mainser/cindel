final class CindelRealworldReport {
  const CindelRealworldReport({
    required this.databaseDirectory,
    required this.steps,
  });

  final String databaseDirectory;
  final List<String> steps;
}

final class CindelRealworldFailure extends Error {
  CindelRealworldFailure(this.message);

  final String message;

  @override
  String toString() => 'CindelRealworldFailure: $message';
}
