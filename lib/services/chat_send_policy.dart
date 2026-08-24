/// 私聊发送按钮可用条件的纯逻辑（输入文字或暂存图片任一存在且 AI 未在回复），
/// 抽出便于单元测试；chat_screen 的 canSend 直接复用。
class ChatSendPolicy {
  ChatSendPolicy._();

  static bool canSend({
    required bool hasText,
    required bool hasPendingImages,
    required bool isSending,
  }) {
    return (hasText || hasPendingImages) && !isSending;
  }
}
