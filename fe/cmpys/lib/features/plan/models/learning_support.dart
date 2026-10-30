import 'plan_models.dart';

class BookTutorial {
  BookTutorial.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      title = j['title'] as String,
      idea = j['idea'] as String,
      content = j['content'] as String,
      minutes = (j['minutes'] as num).toInt(),
      question = j['question'] as String,
      options = List<String>.from(j['options'] as List),
      answer = (j['answer'] as num).toInt(),
      explanation = j['explanation'] as String,
      sourceIds = List<String>.from(j['source_ids'] as List);
  final String id, title, idea, content, question, explanation;
  final int minutes, answer;
  final List<String> options, sourceIds;
}

class BookCompanion {
  BookCompanion.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String?,
      title = j['title'] as String,
      author = j['author'] as String?,
      status = j['status'] as String? ?? 'unavailable',
      scope = j['scope'] as String? ?? '',
      lessons = (j['lessons'] as List? ?? const [])
          .map(
            (e) => BookTutorial.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      sources = (j['sources'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  final String? id, author;
  final String title, status, scope;
  final List<BookTutorial> lessons;
  final List<Map<String, dynamic>> sources;
}

class SupportVideo {
  SupportVideo.fromJson(Map<String, dynamic> j)
    : id = j['videoId'] as String,
      evidenceUrl = j['evidenceUrl'] as String?,
      tryAfter = j['tryAfter'] as String,
      verification = j['verification'] as String,
      material = PlanMaterialDetail(
        title: j['title'] as String,
        type: 'video',
        url: j['url'] as String,
        authorOrCreator: j['creator'] as String,
        reason: j['whyWatch'] as String,
        durationMinutes: j['seconds'] == null
            ? null
            : ((j['seconds'] as num) / 60).ceil(),
      );
  final String id, tryAfter, verification;
  final String? evidenceUrl;
  final PlanMaterialDetail material;
}

class LearningSupport {
  LearningSupport.fromJson(Map<String, dynamic> j)
    : status = j['status'] as String? ?? 'unavailable',
      books = (j['books'] as List? ?? const [])
          .map(
            (e) => BookCompanion.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      videos = (j['videos'] as List? ?? const [])
          .map(
            (e) => SupportVideo.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      idea = j['idea'] == null
          ? null
          : Map<String, dynamic>.from(j['idea'] as Map);
  final String status;
  final List<BookCompanion> books;
  final List<SupportVideo> videos;
  final Map<String, dynamic>? idea;
  bool get checking =>
      status == 'checking' || books.any((b) => b.status == 'checking');
}
