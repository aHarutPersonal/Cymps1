// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'daily_insight.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$DailyInsightImpl _$$DailyInsightImplFromJson(Map<String, dynamic> json) =>
    _$DailyInsightImpl(
      title: json['title'] as String,
      content: json['content'] as String,
      category: json['category'] as String,
      idolName: json['idolName'] as String?,
    );

Map<String, dynamic> _$$DailyInsightImplToJson(_$DailyInsightImpl instance) =>
    <String, dynamic>{
      'title': instance.title,
      'content': instance.content,
      'category': instance.category,
      'idolName': instance.idolName,
    };
