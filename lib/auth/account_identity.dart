final class AccountIdentity {
  const AccountIdentity({
    required this.origin,
    required this.userId,
    required this.systemId,
  });

  final Uri origin;
  final int userId;
  final int systemId;

  bool matchesStored({
    required String? origin,
    required int? userId,
    required int? systemId,
  }) =>
      origin == this.origin.toString() &&
      userId == this.userId &&
      systemId == this.systemId;

  List<Object> get storageKeyParts => [origin.toString(), userId, systemId];

  @override
  bool operator ==(Object other) =>
      other is AccountIdentity &&
      other.origin == origin &&
      other.userId == userId &&
      other.systemId == systemId;

  @override
  int get hashCode => Object.hash(origin, userId, systemId);
}
