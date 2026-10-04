class NewsSubmission {
  const NewsSubmission(
      {required this.content,
      required this.heading,
      required this.headingDefault,
      required this.addToNews,
      required this.withNotification,
      this.recipients});
  final String content;
  final String? heading;
  final String headingDefault;
  final bool addToNews;
  final bool withNotification;
  final List<String>? recipients;
}
