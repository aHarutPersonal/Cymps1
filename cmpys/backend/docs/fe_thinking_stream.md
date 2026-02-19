# Frontend Update: AI Thinking Stream for Idol Import

## Overview

Update the idol import loading screen to show dynamic "AI thinking" text that appears progressively like a typewriter, making the wait time more engaging.

## API Response Changes

The `GET /api/v1/jobs/{jobId}` endpoint now returns a new `thinkingStream` field:

```json
{
  "id": "uuid",
  "idolId": "uuid",
  "idolName": "Warren Buffett",
  "status": "running",
  "step": "extracting_achievements",
  "progressPercent": 45,
  "thinkingStream": {
    "currentLine": "Found something interesting from their early career...",
    "completedLines": [
      "This is the exciting part - finding their achievements...",
      "I'm looking for concrete milestones, not just fame..."
    ],
    "insight": "Real milestones are things you could replicate.",
    "step": "extracting_achievements",
    "stepProgress": 75
  },
  "previewAchievements": ["Founded Company X", "Published Book Y"],
  "previewDomains": ["business", "investing"]
}
```

### Field Descriptions

| Field | Type | Description |
|-------|------|-------------|
| `currentLine` | `String` | The line currently being "typed" - animate with typewriter effect |
| `completedLines` | `List<String>` | Lines already shown - display immediately with checkmark |
| `insight` | `String?` | Optional insight/tip - show as subtle aside |
| `step` | `String` | Current processing step name |
| `stepProgress` | `int` | Progress within current step (0-100) |
| `previewAchievements` | `List<String>?` | Top achievements found (available after 60%) |
| `previewDomains` | `List<String>?` | Idol's domains (available after 25%) |

## Dart Model

```dart
class ThinkingStream {
  final String currentLine;
  final List<String> completedLines;
  final String? insight;
  final String step;
  final int stepProgress;

  ThinkingStream({
    required this.currentLine,
    required this.completedLines,
    this.insight,
    required this.step,
    required this.stepProgress,
  });

  factory ThinkingStream.fromJson(Map<String, dynamic> json) {
    return ThinkingStream(
      currentLine: json['currentLine'] as String,
      completedLines: (json['completedLines'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      insight: json['insight'] as String?,
      step: json['step'] as String,
      stepProgress: json['stepProgress'] as int,
    );
  }
}

class JobStatus {
  final String id;
  final String? idolId;
  final String? idolName;
  final String status;
  final String? step;
  final int progressPercent;
  final String? errorMessage;
  final ThinkingStream? thinkingStream;
  final List<String>? previewAchievements;
  final List<String>? previewDomains;

  JobStatus({
    required this.id,
    this.idolId,
    this.idolName,
    required this.status,
    this.step,
    required this.progressPercent,
    this.errorMessage,
    this.thinkingStream,
    this.previewAchievements,
    this.previewDomains,
  });

  factory JobStatus.fromJson(Map<String, dynamic> json) {
    return JobStatus(
      id: json['id'] as String,
      idolId: json['idolId'] as String?,
      idolName: json['idolName'] as String?,
      status: json['status'] as String,
      step: json['step'] as String?,
      progressPercent: json['progressPercent'] as int,
      errorMessage: json['errorMessage'] as String?,
      thinkingStream: json['thinkingStream'] != null
          ? ThinkingStream.fromJson(json['thinkingStream'])
          : null,
      previewAchievements: (json['previewAchievements'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      previewDomains: (json['previewDomains'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );
  }
}
```

## UI Implementation

### 1. Typewriter Text Widget

```dart
class TypewriterText extends StatefulWidget {
  final String text;
  final Duration charDuration;
  final TextStyle? style;
  final VoidCallback? onComplete;

  const TypewriterText({
    Key? key,
    required this.text,
    this.charDuration = const Duration(milliseconds: 30),
    this.style,
    this.onComplete,
  }) : super(key: key);

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> {
  String _displayedText = '';
  int _charIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  @override
  void didUpdateWidget(TypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _charIndex = 0;
      _displayedText = '';
      _startTyping();
    }
  }

  void _startTyping() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.charDuration, (timer) {
      if (_charIndex < widget.text.length) {
        setState(() {
          _displayedText = widget.text.substring(0, _charIndex + 1);
          _charIndex++;
        });
      } else {
        timer.cancel();
        widget.onComplete?.call();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _displayedText,
      style: widget.style,
    );
  }
}
```

### 2. Thinking Stream Display Widget

```dart
class ThinkingStreamWidget extends StatelessWidget {
  final ThinkingStream stream;
  final String? idolName;

  const ThinkingStreamWidget({
    Key? key,
    required this.stream,
    this.idolName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Completed lines with checkmarks
        ...stream.completedLines.map((line) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.check_circle,
                size: 16,
                color: theme.colorScheme.primary.withOpacity(0.7),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  line,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
            ],
          ),
        )),
        
        // Current line with typewriter effect
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Animated thinking indicator
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(
                    theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TypewriterText(
                  text: stream.currentLine,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // Insight (if available)
        if (stream.insight != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    stream.insight!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
```

### 3. Full Import Loading Screen

```dart
class IdolImportLoadingScreen extends StatefulWidget {
  final String jobId;

  const IdolImportLoadingScreen({
    Key? key,
    required this.jobId,
  }) : super(key: key);

  @override
  State<IdolImportLoadingScreen> createState() => _IdolImportLoadingScreenState();
}

class _IdolImportLoadingScreenState extends State<IdolImportLoadingScreen> {
  Timer? _pollTimer;
  JobStatus? _status;
  bool _isComplete = false;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await _fetchStatus();
    });
    _fetchStatus(); // Initial fetch
  }

  Future<void> _fetchStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/jobs/${widget.jobId}'),
        headers: {'Authorization': 'Bearer $token'},
      );
      
      if (response.statusCode == 200) {
        final status = JobStatus.fromJson(jsonDecode(response.body));
        setState(() {
          _status = status;
          _isComplete = status.status == 'completed';
        });
        
        if (_isComplete || status.status == 'failed') {
          _pollTimer?.cancel();
          if (_isComplete) {
            _navigateToIdol(status.idolId!);
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching job status: $e');
    }
  }

  void _navigateToIdol(String idolId) {
    // Delay slightly to show completion message
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => IdolDetailScreen(idolId: idolId),
        ),
      );
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _status;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with idol name
              if (status?.idolName != null) ...[
                Text(
                  'Researching',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status!.idolName!,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
              ],
              
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (status?.progressPercent ?? 0) / 100,
                  minHeight: 6,
                  backgroundColor: theme.colorScheme.surfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${status?.progressPercent ?? 0}% complete',
                style: theme.textTheme.bodySmall,
              ),
              
              const SizedBox(height: 32),
              
              // Thinking stream
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (status?.thinkingStream != null)
                        ThinkingStreamWidget(
                          stream: status!.thinkingStream!,
                          idolName: status.idolName,
                        ),
                      
                      // Preview achievements (once available)
                      if (status?.previewAchievements != null &&
                          status!.previewAchievements!.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text(
                          'Discovered so far:',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...status.previewAchievements!.take(3).map((a) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Icon(
                                Icons.star,
                                size: 14,
                                color: Colors.amber,
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(a)),
                            ],
                          ),
                        )),
                      ],
                      
                      // Domain tags
                      if (status?.previewDomains != null &&
                          status!.previewDomains!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          children: status.previewDomains!.map((d) => Chip(
                            label: Text(d),
                            backgroundColor: theme.colorScheme.secondaryContainer,
                          )).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

## Visual Design Guidelines

### Colors & Styling

```dart
// Suggested color scheme for thinking stream
final thinkingColors = {
  'completedLine': Colors.grey.shade600,
  'currentLine': theme.colorScheme.onSurface,
  'checkIcon': theme.colorScheme.primary.withOpacity(0.7),
  'insightBg': theme.colorScheme.primaryContainer.withOpacity(0.3),
  'insightIcon': theme.colorScheme.primary,
};
```

### Animation Timing

| Element | Duration | Effect |
|---------|----------|--------|
| Typewriter per char | 30-50ms | Natural typing speed |
| Line fade in | 200ms | Smooth appearance |
| Insight slide in | 300ms | Subtle entrance |
| Poll interval | 1500-2000ms | Balance between responsiveness and API load |

### Layout Recommendations

1. **Keep text left-aligned** for natural reading flow
2. **Scroll container** - thinking text grows, so wrap in scrollable area
3. **Fixed header** - idol name and progress bar should stay visible
4. **Bottom padding** - leave room for insights to appear

## Example Text Flow

```
5%  ▸ Searching for reliable sources about Warren Buffett...

15% ✓ Searching for reliable sources about Warren Buffett...
    ✓ Found their Wikipedia page. Reading through it now...
    ▸ There's quite a lot of information here...
    💡 The 'Early life' section often has the best insights.

45% ✓ This is the exciting part - finding their achievements...
    ✓ I'm looking for concrete milestones, not just fame...
    ▸ Found something interesting from their early career...
    💡 Real milestones are things you could replicate.
    
    Discovered so far:
    ⭐ Founded Buffett Partnership Ltd.
    ⭐ Graduated Columbia Business School

100% ✓ All done! Warren Buffett has been fully imported.
     ✓ You can now explore their timeline and compare achievements.
     ▸ Ready when you are!
```

## Error Handling

```dart
// Handle failed jobs
if (status.status == 'failed') {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('Import Failed'),
      content: Text(status.errorMessage ?? 'Something went wrong'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Try Again'),
        ),
      ],
    ),
  );
}
```

## Testing Checklist

- [ ] Typewriter effect animates smoothly
- [ ] Completed lines appear immediately (no re-animation)
- [ ] Insights fade in/out correctly
- [ ] Progress bar updates correctly
- [ ] Preview achievements appear at 60%+
- [ ] Handles job completion → navigation
- [ ] Handles job failure → error dialog
- [ ] Works offline gracefully (shows last cached state)
- [ ] Memory cleanup on dispose (cancel timers)
