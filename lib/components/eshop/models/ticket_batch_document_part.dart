/// Metadata only. Storage keys and signed URLs stay behind document authority.
class TicketBatchDocumentPart {
  const TicketBatchDocumentPart(
      {required this.id,
      required this.key,
      required this.kind,
      required this.state,
      this.pages});
  final String id, key, kind, state;
  final int? pages;
  factory TicketBatchDocumentPart.fromJson(Map<String, dynamic> json) =>
      TicketBatchDocumentPart(
          id: json['id'] as String,
          key: json['key'] as String,
          kind: json['kind'] as String,
          state: json['state'] as String,
          pages: (json['pages'] as num?)?.toInt());
}
