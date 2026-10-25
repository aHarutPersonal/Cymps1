import 'package:integration_test/integration_test.dart';
import '../test/book_availability_test.dart' as availability;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  availability.main();
}
