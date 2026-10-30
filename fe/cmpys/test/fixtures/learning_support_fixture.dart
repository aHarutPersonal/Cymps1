import 'package:cmpys/features/plan/models/learning_support.dart';

Map<String, dynamic> supportFixture({String status = 'ready'}) => {
  'status': status,
  'books': [
    {
      'id': 'companion-1',
      'title': 'A useful book',
      'author': 'An author',
      'status': status,
      'scope':
          'Selected public ideas, with original CMPYS examples and self-checks.',
      'lessons': [
        for (var i = 1; i <= 2; i++)
          {
            'id': 'lesson_$i',
            'title': i == 1
                ? 'Choose a concrete cue'
                : 'Make the action smaller',
            'idea':
                'A recognizable cue helps you identify when to take a specific action.',
            'content':
                '## One useful idea\n\nA concrete cue identifies when to act.\n\n'
                '## Original CMPYS example\n\nAfter breakfast, write one line. The event is clear and the action is small.\n\n'
                '## Try it\n\nChoose an everyday event and one small action you could attach to it.',
            'minutes': 4,
            'question': 'Which choice includes a concrete cue?',
            'options': [
              'After breakfast, write one line.',
              'Become better.',
              'Try someday.',
            ],
            'answer': 0,
            'explanation':
                'After breakfast gives a recognizable cue; one line keeps the action small.',
            'source_ids': ['s1'],
          },
      ],
      'sources': [
        {
          'id': 's1',
          'title': 'Public author explanation',
          'url': 'https://example.org/author',
        },
      ],
    },
  ],
  'idea': status != 'ready'
      ? null
      : {
          'bookId': 'companion-1',
          'lessonId': 'lesson_1',
          'bookTitle': 'A useful book',
          'author': 'An author',
          'title': 'Choose a concrete cue',
          'text': 'A concrete cue makes the next action easier to identify.',
          'application':
              'Use the event you identified in this tutorial as your cue.',
        },
  'videos': status != 'ready'
      ? []
      : [
          {
            'videoId': 'abcdefghijk',
            'title': 'Watch a cue become an action',
            'creator': 'Educational creator',
            'url': 'https://www.youtube.com/watch?v=abcdefghijk',
            'seconds': 240,
            'whyWatch':
                'A demonstration of choosing a specific cue and a small action.',
            'tryAfter':
                'Describe the cue and the action without replaying the demonstration.',
            'verification':
                'Availability and lesson relevance checked against the creator’s description.',
          },
        ],
};

LearningSupport readySupport() => LearningSupport.fromJson(supportFixture());
