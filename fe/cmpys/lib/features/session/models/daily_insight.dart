import 'package:freezed_annotation/freezed_annotation.dart';

part 'daily_insight.freezed.dart';
part 'daily_insight.g.dart';

@freezed
class DailyInsight with _$DailyInsight {
  const factory DailyInsight({
    required String title,
    required String content,
    required String category,
    String? idolName,
  }) = _DailyInsight;

  factory DailyInsight.fromJson(Map<String, dynamic> json) =>
      _$DailyInsightFromJson(json);
}
