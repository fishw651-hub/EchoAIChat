package services

import (
	"encoding/json"
	"testing"
)

func TestChatCompletionRequestMarshalsToolPayload(t *testing.T) {
	t.Parallel()

	req := ChatCompletionRequest{
		Model: "deepseek-v4-flash",
		Messages: []ChatMessage{
			{Role: "user", Content: "帮我写一个角色"},
		},
		Tools: []map[string]interface{}{
			{
				"type": "function",
				"function": map[string]interface{}{
					"name": "ask_user",
				},
			},
		},
		ToolChoice: "required",
	}

	data, err := json.Marshal(req)
	if err != nil {
		t.Fatalf("marshal request: %v", err)
	}

	var got map[string]interface{}
	if err := json.Unmarshal(data, &got); err != nil {
		t.Fatalf("unmarshal request: %v", err)
	}

	if got["tool_choice"] != "required" {
		t.Fatalf("tool_choice = %v, want required", got["tool_choice"])
	}
	if tools, ok := got["tools"].([]interface{}); !ok || len(tools) != 1 {
		t.Fatalf("tools = %#v, want one tool definition", got["tools"])
	}
}

func TestChatCompletionResponseParsesReasoningAndToolCalls(t *testing.T) {
	t.Parallel()

	body := []byte(`{
		"id": "chatcmpl-test",
		"choices": [{
			"index": 0,
			"message": {
				"role": "assistant",
				"content": "",
				"reasoning_content": "需要先询问用户偏好的风格。",
				"tool_calls": [{
					"id": "call_1",
					"type": "function",
					"function": {
						"name": "ask_user",
						"arguments": "{\"question\":\"想要哪种风格？\"}"
					}
				}]
			},
			"finish_reason": "tool_calls"
		}]
	}`)

	var got ChatCompletionResponse
	if err := json.Unmarshal(body, &got); err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}

	message := got.Choices[0].Message
	if message.ReasoningContent == "" {
		t.Fatal("reasoning_content was not parsed")
	}
	if len(message.ToolCalls) != 1 {
		t.Fatalf("tool_calls length = %d, want 1", len(message.ToolCalls))
	}
	if message.ToolCalls[0].Function.Name != "ask_user" {
		t.Fatalf("tool name = %q, want ask_user", message.ToolCalls[0].Function.Name)
	}
}
