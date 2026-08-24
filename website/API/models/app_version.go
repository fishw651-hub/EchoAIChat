package models

import "time"

type AppVersion struct {
	ID            uint      `json:"id"`
	Platform      string    `json:"platform"`
	Version       string    `json:"version"`
	VersionCode   int       `json:"version_code"`
	FilePath      string    `json:"file_path"`
	FileSize      int64     `json:"file_size"`
	ReleaseNotes  string    `json:"release_notes"`
	IsForce       bool      `json:"is_force"`
	Status        int       `json:"status"`
	DownloadCount int       `json:"download_count"`
	DownloadURL   string    `json:"download_url"` // 外部直链（非空时优先走此链接，节省主服务器流量）
	CreatedAt     time.Time `json:"created_at"`
}
