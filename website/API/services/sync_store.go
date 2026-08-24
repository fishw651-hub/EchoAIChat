package services

import (
	"context"

	"aichat-api/database"
	"aichat-api/models"
)

// sync_store.go — 同步相关表（SyncXxx 动态注册名 + SyncTombstone）数据访问薄封装，
// 供 handlers 层使用。registerName 由 handlers 的表名白名单映射给出，不在此校验。

// SyncTx 是 database.Tx 的别名：sync v2 事务内操作通过 WithSyncTx 回调暴露，
// handlers 直接使用其方法而无需 import database 包。
type SyncTx = database.Tx

// WithSyncTx 在事务中执行 fn（语义同 database.DB.WithTx）。
func WithSyncTx(ctx context.Context, fn func(*SyncTx) error) error {
	return database.Get().WithTx(ctx, fn)
}

// SyncMaxUpdatedAtByUserID 返回指定同步表内该用户最近 updated_at。
func SyncMaxUpdatedAtByUserID(registerName string, userID uint) string {
	return database.Get().Register(registerName).MaxUpdatedAtByUserID(userID)
}

// SyncFindAllByUserID 返回指定同步表内该用户全部行。
func SyncFindAllByUserID(registerName string, userID uint) []map[string]interface{} {
	return database.Get().Register(registerName).FindAllByUserID(userID)
}

// SyncBatchUpsertByUserIDClientID 批量 upsert 同步行；部分失败返回已写入数与错误。
func SyncBatchUpsertByUserIDClientID(registerName string, userID uint, items []map[string]interface{}) (int, error) {
	return database.Get().Register(registerName).BatchUpsertByUserIDClientID(userID, items)
}

// SyncBatchDeleteByUserIDClientID 按 client_id 批量删除同步行，返回删除数。
func SyncBatchDeleteByUserIDClientID(registerName string, userID uint, clientIDs []string) int {
	return database.Get().Register(registerName).BatchDeleteByUserIDClientID(userID, clientIDs)
}

// SyncTombstonesByUserID 返回该用户全部墓碑。
func SyncTombstonesByUserID(userID uint) []map[string]interface{} {
	return database.Get().Register("SyncTombstone").FindAllByUserID(userID)
}

// SyncTombstoneMaxUpdatedAtByUserID 返回该用户墓碑表最近 updated_at。
func SyncTombstoneMaxUpdatedAtByUserID(userID uint) string {
	return database.Get().Register("SyncTombstone").MaxUpdatedAtByUserID(userID)
}

// SyncInsertTombstones 批量插入墓碑记录（一次落盘）。
func SyncInsertTombstones(rows []map[string]interface{}) (int, error) {
	return database.Get().Register("SyncTombstone").BatchInsertMaps(rows)
}

// SyncDeleteTombstoneByID 按主键删除墓碑；返回是否实际删除。
func SyncDeleteTombstoneByID(id uint) bool {
	return database.Get().Register("SyncTombstone").Delete(id)
}

// SyncInsertTombstoneRecord 在事务外插入单条墓碑记录。
func SyncInsertTombstoneRecord(tombstone *models.SyncTombstone) error {
	return database.Get().Register("SyncTombstone").Insert(tombstone)
}
