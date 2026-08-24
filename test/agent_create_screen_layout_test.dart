import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'agent creation keeps the guided sections and both completion paths',
    () {
      final source = File(
        'lib/screens/agent_create_screen.dart',
      ).readAsStringSync();

      expect(
        source,
        contains("import '../widgets/creation_form_section.dart';"),
      );
      expect(source, contains("Key('agent-creation-basic')"));
      expect(source, contains("Key('agent-creation-quick-actions')"));
      expect(source, contains("Key('agent-creation-core')"));
      expect(source, contains("Key('agent-real-info-settings')"));
      expect(source, contains("Key('agent-max-response-length')"));
      expect(source, contains('min: 50'));
      expect(source, contains('max: 800'));
      expect(source, contains('divisions: 75'));
      expect(source, contains("Key('agent-more-settings')"));
      expect(source, contains("Key('agent-creation-submit-actions')"));
      expect(source, contains('CreationQuickActions('));
      expect(source, contains('CreationSubmitActions('));
      expect(source, contains('onUploadPressed: _saveAndUpload'));
      expect(source, contains('clearOpeningLine: opening.isEmpty'));
      expect(
        source.indexOf("Key('agent-real-info-settings')"),
        lessThan(source.indexOf("Key('agent-more-settings')")),
      );
    },
  );
}
