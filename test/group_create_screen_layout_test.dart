import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('group creation exposes type selection and the upload path', () {
    final source = File(
      'lib/screens/group_create_screen.dart',
    ).readAsStringSync();

    expect(source, contains("import '../widgets/creation_form_section.dart';"));
    expect(source, contains("import 'network_upload_screen.dart';"));
    expect(source, contains("Key('group-creation-type')"));
    expect(source, contains("Key('group-creation-members')"));
    expect(source, contains("Key('group-opening-settings')"));
    expect(source, contains("Key('group-more-settings')"));
    expect(source, contains("Key('group-creation-submit-actions')"));
    expect(source, contains('SegmentedButton<bool>'));
    expect(source, contains('Future<GroupChat?> _persistGroup'));
    expect(source, contains('Future<void> _saveAndUpload()'));
    expect(
      source,
      contains("NetworkUploadScreen(type: 'group', localGroup: group)"),
    );
    expect(source, contains('CreationSubmitActions('));
    expect(source, contains('_setSimulatorMode(values.first)'));
    expect(source, contains('_importedSpeakers = null'));
    expect(source, contains('Future<void> _syncEditedMembers'));
    expect(source, contains('await notifier.removeMember'));
    expect(source, contains('await notifier.addMember'));
    expect(source, contains('await notifier.updateMember'));
    expect(source, contains('_moreSettingsController.expand()'));
    expect(source, contains('_openingFocusNode.requestFocus()'));
    expect(source, contains('_openingSpeakerAgentId'));
    expect(source, contains('openingSpeakerAgentId: _openingSpeakerAgentId'));
    expect(source, contains('narratorAgentId'));
    expect(source, contains('GroupChatScreen(groupId: group.id)'));
    expect(source, contains('bool _editingDataLoaded = false'));
    expect(source, contains('isEditing && !_editingDataLoaded'));
  });
}
