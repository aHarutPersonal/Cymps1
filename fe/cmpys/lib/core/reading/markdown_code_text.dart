/// Undo exactly the escaping applied by package:markdown to a code node.
/// One pass is essential: source `&gt;` must stay literal `&gt;`, not become `>`.
/// Share this boundary between semantic parsing, display and narration.
String markdownCodeText(String text, {bool encoded = true}) => !encoded
    ? text
    : text.replaceAllMapped(
        RegExp(r'&(amp|lt|gt|quot);'),
        (match) => switch (match[1]) {
          'amp' => '&',
          'lt' => '<',
          'gt' => '>',
          'quot' => '"',
          _ => match[0]!,
        },
      );
