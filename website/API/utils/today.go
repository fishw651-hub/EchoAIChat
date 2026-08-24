package utils

import "time"

// cnZone 中国时区（UTC+8）。配额/计费的"今日"统一以此为准，
// 避免服务器本地时区（如 UTC）导致北京时间 0–8 点配额不刷新。
var cnZone = time.FixedZone("CST", 8*3600)

// TodayCN 返回中国时区下的今日日期（yyyy-MM-dd）
func TodayCN() string {
	return time.Now().In(cnZone).Format("2006-01-02")
}
