import 'package:integration_test/integration_test.dart';
import '../test/onboarding_resilience_test.dart' as onboarding;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  onboarding.main();
}
