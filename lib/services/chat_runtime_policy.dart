class ChatRuntimePolicy {
  final String model;
  final bool thinkingMode;
  final double? temperature;

  const ChatRuntimePolicy({
    required this.model,
    required this.thinkingMode,
    required this.temperature,
  });

  static const standard = ChatRuntimePolicy(
    model: 'deepseek-v4-flash',
    thinkingMode: false,
    temperature: 1.3,
  );

  static const qualityTask = ChatRuntimePolicy(
    model: 'deepseek-v4-flash',
    thinkingMode: true,
    temperature: null,
  );

  static const simulator = qualityTask;
}
