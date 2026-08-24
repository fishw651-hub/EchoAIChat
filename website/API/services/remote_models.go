package services

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// ValidateRemoteBaseURL 校验远程站点地址（SSRF 基本防护，思路同 isSafeDownloadURL）：
// 仅允许 http/https scheme 且必须带 host；返回裁剪尾部 "/" 后的地址。
func ValidateRemoteBaseURL(rawURL string) (string, error) {
	trimmed := strings.TrimRight(strings.TrimSpace(rawURL), "/")
	if trimmed == "" {
		return "", fmt.Errorf("API 地址不能为空")
	}
	u, err := url.Parse(trimmed)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Hostname() == "" {
		return "", fmt.Errorf("API 地址仅支持 http/https")
	}
	return trimmed, nil
}

// remoteModelsHTTPClient 独立 client（15s 超时），避免影响全局默认 client。
var remoteModelsHTTPClient = &http.Client{Timeout: 15 * time.Second}

// FetchRemoteModels 代理请求 {baseURL}/models（OpenAI 格式响应），返回模型 id 列表。
func FetchRemoteModels(baseURL, apiKey string) ([]string, error) {
	base, err := ValidateRemoteBaseURL(baseURL)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequest(http.MethodGet, base+"/models", nil)
	if err != nil {
		return nil, fmt.Errorf("构建请求失败: %v", err)
	}
	if key := strings.TrimSpace(apiKey); key != "" {
		req.Header.Set("Authorization", "Bearer "+key)
	}
	resp, err := remoteModelsHTTPClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("请求上游失败: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("上游返回状态 %d", resp.StatusCode)
	}
	var payload ModelsResponse
	if err := json.NewDecoder(io.LimitReader(resp.Body, 4<<20)).Decode(&payload); err != nil {
		return nil, fmt.Errorf("解析上游响应失败: %v", err)
	}
	ids := make([]string, 0, len(payload.Data))
	for _, m := range payload.Data {
		if id := strings.TrimSpace(m.ID); id != "" {
			ids = append(ids, id)
		}
	}
	if len(ids) == 0 {
		return nil, fmt.Errorf("上游未返回任何模型")
	}
	return ids, nil
}
