package utils

import (
	"mime/multipart"
	"path/filepath"
	"strings"

	"aichat-api/config"
)

func ValidateAvatar(file *multipart.FileHeader) string {
	maxSize := int64(config.AppConfig.Upload.MaxSizeMB) * 1024 * 1024
	if file.Size > maxSize {
		return "文件大小超过限制"
	}

	ext := strings.ToLower(filepath.Ext(file.Filename))
	if ext == "" {
		return "无法识别文件类型"
	}
	ext = ext[1:]

	allowed := false
	for _, t := range config.AppConfig.Upload.AllowedTypes {
		if t == ext {
			allowed = true
			break
		}
	}
	if !allowed {
		return "不支持的文件类型，仅支持: " + strings.Join(config.AppConfig.Upload.AllowedTypes, ", ")
	}

	return ""
}

func IsValidEmail(email string) bool {
	if len(email) < 3 || len(email) > 254 {
		return false
	}
	at := strings.Index(email, "@")
	if at <= 0 || at == len(email)-1 {
		return false
	}
	return strings.Contains(email[at:], ".")
}

// MaskEmail 邮箱打码（日志用，PII 不明文落日志）：alice@example.com → a***e@example.com
func MaskEmail(email string) string {
	at := strings.Index(email, "@")
	if at <= 0 {
		return "***"
	}
	local := email[:at]
	if len(local) == 1 {
		return local + "***" + email[at:]
	}
	return local[:1] + "***" + local[len(local)-1:] + email[at:]
}
