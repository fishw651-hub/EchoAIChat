package services

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"io"
	"strings"
)

func NormalizeEncryptionKey(key string) []byte {
	if len(key) < 32 {
		key = key + "00000000000000000000000000000000"
	}
	return []byte(key[:32])
}

func Encrypt(plaintext string, key []byte) (string, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}

	aesGCM, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}

	nonce := make([]byte, aesGCM.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}

	ciphertext := aesGCM.Seal(nonce, nonce, []byte(plaintext), nil)
	return base64.StdEncoding.EncodeToString(ciphertext), nil
}

func Decrypt(encoded string, key []byte) (string, error) {
	ciphertext, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return "", err
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}

	aesGCM, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}

	nonceSize := aesGCM.NonceSize()
	if len(ciphertext) < nonceSize {
		return "", errors.New("密文太短")
	}

	nonce, ciphertext := ciphertext[:nonceSize], ciphertext[nonceSize:]
	plaintext, err := aesGCM.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		return "", err
	}

	return string(plaintext), nil
}

// DecryptWithConfiguredKeys 优先使用当前主密钥，并兼容密钥优先级修复前
// 可能由旧 config.yaml 密钥写入的历史密文。
// 密钥来源由 ConfigureRuntime 注入（main 启动时装配），不再直读全局配置。
func DecryptWithConfiguredKeys(encoded string) (string, error) {
	primaryKey, configured := runtimeEncryptionKey()
	if !configured {
		return "", errors.New("加密配置未初始化")
	}
	fallbackKeys := runtimeEncryptionFallbackKeys()
	keys := make([]string, 0, 1+len(fallbackKeys))
	keys = append(keys, primaryKey)
	keys = append(keys, fallbackKeys...)
	seen := make(map[string]struct{}, len(keys))
	var lastErr error
	for index, key := range keys {
		key = strings.TrimSpace(key)
		// 保留旧行为：测试或迁移代码中的空主密钥会被零填充；
		// 空的后备项没有意义，直接忽略。
		if key == "" && index > 0 {
			continue
		}
		if _, exists := seen[key]; exists {
			continue
		}
		seen[key] = struct{}{}
		plain, err := Decrypt(encoded, NormalizeEncryptionKey(key))
		if err == nil {
			return plain, nil
		}
		lastErr = err
	}
	if lastErr == nil {
		lastErr = errors.New("没有可用的解密密钥")
	}
	return "", lastErr
}
