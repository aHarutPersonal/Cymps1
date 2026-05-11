import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/content_resources_repository.dart';
import '../models/content_resource.dart';

final vaultResourcesProvider = FutureProvider<List<ContentResource>>((ref) {
  return ref.watch(contentResourcesRepositoryProvider).listVaultResources();
});
