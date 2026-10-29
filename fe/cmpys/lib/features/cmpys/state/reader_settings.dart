import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import 'cmpys_store.dart';

/// Reading settings (design `st.readSize` / `st.readTheme`), kept on this
/// device in [cmpysStoreProvider]. Shared by the tutorial reader and, later,
/// the book reader.
class ReaderSettings {
  const ReaderSettings({this.size = 1, this.theme = ReaderTheme.light});

  /// 0 "A", 1 "A+", 2 "A++".
  final int size;
  final ReaderTheme theme;

  /// Body text sizes for "A", "A+" and "A++" (`[16, 17.5, 19.5]`).
  static const fontSizes = [16.0, 17.5, 19.5];

  /// The segment labels, in [size] order.
  static const sizeLabels = ['A', 'A+', 'A++'];

  double get fontSize => fontSizes[size.clamp(0, 2)];
}

final readerSettingsProvider = Provider<ReaderSettings>((ref) {
  final (size, theme) = ref.watch(
    cmpysStoreProvider.select(
      (state) => (state.settings.readSize, state.settings.readTheme),
    ),
  );
  return ReaderSettings(size: size, theme: ReaderTheme.fromName(theme));
});

/// Writes the reader settings through [cmpysStoreProvider].
extension ReaderSettingsWriter on WidgetRef {
  void setReaderSize(int size) =>
      read(cmpysStoreProvider.notifier).setReadSize(size);

  void setReaderTheme(ReaderTheme theme) =>
      read(cmpysStoreProvider.notifier).setReadTheme(theme.name);
}
