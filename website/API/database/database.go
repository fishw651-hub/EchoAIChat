package database

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"sync"
	"time"

	_ "modernc.org/sqlite"
)

const migrationVersion = 1

// maxOpenConns 是 SQLite 连接池上限。WAL 模式支持多读者 + 单写者：
// 写路径由 DB.writeMu 在 Go 侧串行化（同时只有一个写者），读查询不持锁，
// 可并行占用多个连接。busy_timeout 通过 DSN _pragma 对池内每条连接生效。
const maxOpenConns = 8

type DB struct {
	dir    string
	sql    *sql.DB
	tables map[string]*Table
	mu     sync.RWMutex
	// writeMu 串行化所有写路径。纪律：任何写 / 读-改-写 / 事务（WithTx）必须
	// 全程持有 writeMu（事务从 Begin 到 Commit/Rollback），纯读查询不持锁。
	// WAL 下 SQLite 只允许单写者，持锁既防止并发 RMW 丢更新，也避免两个
	// 写者互撞 SQLITE_BUSY。
	writeMu sync.Mutex
}

type Table struct {
	name string
	db   *DB
}

type Tx struct {
	tx *sql.Tx
}

func (tx *Tx) SQL() *sql.Tx { return tx.tx }

func (tx *Tx) FindByID(tableName string, id uint, dest interface{}) (bool, error) {
	row, err := fetchOne(context.Background(), tx.tx, "SELECT payload FROM records WHERE table_name = ? AND id = ?", tableName, id)
	if err != nil || row == nil {
		return false, err
	}
	fromMap(row, dest)
	return true, nil
}

func (tx *Tx) FindOne(tableName string, where Filter, dest interface{}) (bool, error) {
	query, args, pushdown := filterSQL("SELECT payload FROM records WHERE table_name = ?", tableName, where)
	if !pushdown {
		query, args = "SELECT payload FROM records WHERE table_name = ?", []interface{}{tableName}
	}
	rows, err := fetchRows(context.Background(), tx.tx, query, args...)
	if err != nil {
		return false, err
	}
	for _, row := range rows {
		if pushdown || where == nil || where.Match(row) {
			fromMap(row, dest)
			return true, nil
		}
	}
	return false, nil
}

func (tx *Tx) Replace(tableName string, id uint, value interface{}) error {
	row := toMap(value)
	row["ID"] = float64(id)
	return upsertRecord(context.Background(), tx.tx, tableName, id, row)
}

func (tx *Tx) Insert(tableName string, value interface{}) error {
	id, err := nextID(context.Background(), tx.tx, tableName)
	if err != nil {
		return err
	}
	row := toMap(value)
	row["ID"] = float64(id)
	now := time.Now().UTC().Format(time.RFC3339Nano)
	if _, ok := row["CreatedAt"]; ok {
		row["CreatedAt"] = now
	}
	if _, ok := row["UpdatedAt"]; ok {
		row["UpdatedAt"] = now
	}
	if err := upsertRecord(context.Background(), tx.tx, tableName, id, row); err != nil {
		return err
	}
	setStructField(value, "ID", id)
	return nil
}

func (tx *Tx) FindAllByUserID(tableName string, userID uint) ([]map[string]interface{}, error) {
	return fetchRows(context.Background(), tx.tx,
		"SELECT payload FROM records WHERE table_name = ? AND user_id = ?", tableName, userID)
}

func (tx *Tx) UpsertByUserIDClientID(tableName string, userID uint, item map[string]interface{}) error {
	clientID := rowClientID(item)
	if clientID == "" {
		return errors.New("client_id 不能为空")
	}
	row := cloneMap(item)
	row["UserID"] = userID
	row["ClientID"] = clientID
	id, found, err := findIDByUserClient(context.Background(), tx.tx, tableName, userID, clientID)
	if err != nil {
		return err
	}
	if found {
		existing, err := fetchOne(context.Background(), tx.tx,
			"SELECT payload FROM records WHERE table_name = ? AND id = ?", tableName, id)
		if err != nil {
			return err
		}
		for key, value := range row {
			existing[key] = value
		}
		row = existing
	} else {
		id, err = nextID(context.Background(), tx.tx, tableName)
		if err != nil {
			return err
		}
		row["ID"] = float64(id)
		if _, ok := row["CreatedAt"]; !ok {
			row["CreatedAt"] = time.Now().UTC().Format(time.RFC3339Nano)
		}
	}
	if _, ok := row["UpdatedAt"]; !ok {
		row["UpdatedAt"] = time.Now().UTC().Format(time.RFC3339Nano)
	}
	return upsertRecord(context.Background(), tx.tx, tableName, id, row)
}

func (tx *Tx) DeleteByUserIDClientID(tableName string, userID uint, clientID string) (bool, error) {
	result, err := tx.tx.ExecContext(context.Background(),
		"DELETE FROM records WHERE table_name = ? AND user_id = ? AND client_id = ?",
		tableName, userID, clientID)
	if err != nil {
		return false, err
	}
	affected, err := result.RowsAffected()
	return err == nil && affected > 0, err
}

var DBInstance *DB

func Init(dir string) error {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}

	if DBInstance != nil {
		_ = DBInstance.Close()
	}

	dbPath := filepath.Join(dir, "aichat.db")
	// busy_timeout / foreign_keys / WAL 走 DSN _pragma：连接池有多条连接后，
	// 用 Exec 设置 PRAGMA 只作用于执行它的那条连接，新开的连接会丢失配置。
	dsn := "file:" + filepath.ToSlash(dbPath) +
		"?_pragma=busy_timeout(5000)&_pragma=foreign_keys(1)&_pragma=journal_mode(WAL)"
	sqlDB, err := sql.Open("sqlite", dsn)
	if err != nil {
		return fmt.Errorf("打开 SQLite 数据库失败: %w", err)
	}
	sqlDB.SetMaxOpenConns(maxOpenConns)
	sqlDB.SetMaxIdleConns(maxOpenConns)

	db := &DB{dir: dir, sql: sqlDB, tables: make(map[string]*Table)}
	if err := db.configure(); err != nil {
		_ = sqlDB.Close()
		return err
	}
	if err := db.migrateLegacyJSON(); err != nil {
		_ = sqlDB.Close()
		return err
	}
	DBInstance = db
	return nil
}

func (db *DB) configure() error {
	for _, statement := range []string{
		"PRAGMA journal_mode=WAL",
		"PRAGMA foreign_keys=ON",
		"PRAGMA busy_timeout=5000",
		`CREATE TABLE IF NOT EXISTS records (
			table_name TEXT NOT NULL,
			id INTEGER NOT NULL,
			payload BLOB NOT NULL,
			user_id INTEGER,
			client_id TEXT,
			order_no TEXT,
			status TEXT,
			updated_at TEXT,
			PRIMARY KEY (table_name, id)
		)`,
		"CREATE TABLE IF NOT EXISTS table_sequences (table_name TEXT PRIMARY KEY, seq INTEGER NOT NULL)",
		"CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL)",
		"CREATE INDEX IF NOT EXISTS idx_records_user ON records(table_name, user_id)",
		"CREATE UNIQUE INDEX IF NOT EXISTS idx_records_client ON records(table_name, user_id, client_id) WHERE client_id IS NOT NULL AND client_id <> ''",
		"CREATE INDEX IF NOT EXISTS idx_records_order ON records(table_name, order_no)",
		"CREATE INDEX IF NOT EXISTS idx_records_status ON records(table_name, status)",
		"CREATE INDEX IF NOT EXISTS idx_records_updated ON records(table_name, user_id, updated_at)",
	} {
		if _, err := db.sql.Exec(statement); err != nil {
			return fmt.Errorf("初始化 SQLite schema 失败: %w", err)
		}
	}
	return nil
}

func (db *DB) migrateLegacyJSON() error {
	var applied int
	err := db.sql.QueryRow("SELECT COUNT(*) FROM schema_migrations WHERE version = ?", migrationVersion).Scan(&applied)
	if err != nil {
		return fmt.Errorf("读取迁移状态失败: %w", err)
	}
	if applied > 0 {
		return nil
	}

	entries, err := os.ReadDir(db.dir)
	if err != nil {
		return fmt.Errorf("读取旧数据目录失败: %w", err)
	}

	tx, err := db.sql.BeginTx(context.Background(), nil)
	if err != nil {
		return fmt.Errorf("开始迁移事务失败: %w", err)
	}
	rollback := func(cause error) error {
		_ = tx.Rollback()
		return cause
	}

	var legacyFiles []string
	for _, entry := range entries {
		if entry.IsDir() || !strings.EqualFold(filepath.Ext(entry.Name()), ".json") {
			continue
		}
		path := filepath.Join(db.dir, entry.Name())
		data, err := os.ReadFile(path)
		if err != nil {
			return rollback(fmt.Errorf("读取旧数据 %s 失败: %w", entry.Name(), err))
		}
		if len(strings.TrimSpace(string(data))) == 0 {
			legacyFiles = append(legacyFiles, path)
			continue
		}

		var rows []map[string]interface{}
		if err := json.Unmarshal(data, &rows); err != nil {
			return rollback(fmt.Errorf("导入旧数据 %s 失败: %w", entry.Name(), err))
		}
		tableName := strings.TrimSuffix(entry.Name(), filepath.Ext(entry.Name()))
		var maxID uint
		for _, row := range rows {
			id, ok := mapID(row)
			if !ok || id == 0 {
				return rollback(fmt.Errorf("旧数据 %s 包含无效 ID", entry.Name()))
			}
			if id > maxID {
				maxID = id
			}
			if err := upsertRecord(context.Background(), tx, tableName, id, row); err != nil {
				return rollback(fmt.Errorf("导入 %s/%d 失败: %w", tableName, id, err))
			}
		}
		if _, err := tx.Exec(`INSERT INTO table_sequences(table_name, seq) VALUES(?, ?)
			ON CONFLICT(table_name) DO UPDATE SET seq = excluded.seq`, tableName, maxID); err != nil {
			return rollback(fmt.Errorf("写入 %s 序列失败: %w", tableName, err))
		}
		legacyFiles = append(legacyFiles, path)
	}

	if _, err := tx.Exec("INSERT INTO schema_migrations(version, applied_at) VALUES(?, ?)", migrationVersion, time.Now().UTC().Format(time.RFC3339Nano)); err != nil {
		return rollback(fmt.Errorf("写入迁移标记失败: %w", err))
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("提交旧数据迁移失败: %w", err)
	}

	if len(legacyFiles) == 0 {
		return nil
	}
	backupDir := filepath.Join(db.dir, "legacy-json-"+time.Now().UTC().Format("20060102T150405Z"))
	if err := os.MkdirAll(backupDir, 0o700); err != nil {
		return fmt.Errorf("创建旧数据备份目录失败: %w", err)
	}
	for _, path := range legacyFiles {
		if err := os.Rename(path, filepath.Join(backupDir, filepath.Base(path))); err != nil {
			return fmt.Errorf("备份旧数据 %s 失败: %w", filepath.Base(path), err)
		}
	}
	return nil
}

func (db *DB) Close() error {
	db.mu.Lock()
	defer db.mu.Unlock()
	if db.sql == nil {
		return nil
	}
	err := db.sql.Close()
	db.sql = nil
	db.tables = nil
	if DBInstance == db {
		DBInstance = nil
	}
	return err
}

func Get() *DB { return DBInstance }

func (db *DB) SQL() *sql.DB { return db.sql }

func (db *DB) WithTx(ctx context.Context, fn func(*Tx) error) error {
	if ctx == nil {
		ctx = context.Background()
	}
	// 事务 = 读-改-写整体：从 Begin 到 Commit/Rollback 全程持有写锁，
	// 既防止并发事务丢更新，也保证池化后任意时刻只有一个写者。
	db.writeMu.Lock()
	defer db.writeMu.Unlock()
	tx, err := db.sql.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	if err := fn(&Tx{tx: tx}); err != nil {
		_ = tx.Rollback()
		return err
	}
	return tx.Commit()
}

// execWrite 执行单语句写操作（DELETE 等）。与 WithTx 同纪律：持有写锁，
// 避免与进行中的写事务互撞 SQLITE_BUSY。
func (db *DB) execWrite(query string, args ...interface{}) (sql.Result, error) {
	db.writeMu.Lock()
	defer db.writeMu.Unlock()
	return db.sql.Exec(query, args...)
}

func (db *DB) Register(name string) *Table {
	db.mu.Lock()
	defer db.mu.Unlock()
	if table, ok := db.tables[name]; ok {
		return table
	}
	table := &Table{name: name, db: db}
	db.tables[name] = table
	return table
}

func (t *Table) Insert(v interface{}) error {
	m := toMap(v)
	return t.db.WithTx(context.Background(), func(tx *Tx) error {
		id, err := nextID(context.Background(), tx.tx, t.name)
		if err != nil {
			return err
		}
		m["ID"] = float64(id)
		now := time.Now().UTC().Format(time.RFC3339Nano)
		if _, ok := m["CreatedAt"]; ok {
			m["CreatedAt"] = now
		}
		if _, ok := m["UpdatedAt"]; ok {
			m["UpdatedAt"] = now
		}
		if err := upsertRecord(context.Background(), tx.tx, t.name, id, m); err != nil {
			return err
		}
		setStructField(v, "ID", id)
		return nil
	})
}

// FindByIDE 与 FindByID 相同，但显式区分"记录不存在"与"DB 错误"：
// found=false 且 err=nil 仅表示没有这条记录；err 非 nil 表示查询本身失败，
// 调用方（如鉴权中间件）必须据此返回 5xx 而不是误判为"账户不存在"。
func (t *Table) FindByIDE(id uint, dest interface{}) (bool, error) {
	row, err := fetchOne(context.Background(), t.db.sql, `SELECT payload FROM records WHERE table_name = ? AND id = ?`, t.name, id)
	if err != nil || row == nil {
		return false, err
	}
	fromMap(row, dest)
	return true, nil
}

func (t *Table) FindByID(id uint, dest interface{}) bool {
	found, _ := t.FindByIDE(id, dest)
	return found
}

// FindOneE 与 FindOne 相同，但显式返回 DB 错误（语义同 FindByIDE）。
func (t *Table) FindOneE(where Filter, dest interface{}) (bool, error) {
	rows, err := t.rows(context.Background(), where)
	if err != nil {
		return false, err
	}
	if len(rows) == 0 {
		return false, nil
	}
	fromMap(rows[0], dest)
	return true, nil
}

func (t *Table) FindOne(where Filter, dest interface{}) bool {
	found, _ := t.FindOneE(where, dest)
	return found
}

func (t *Table) FindAll(dest interface{}, where Filter, order string, offset, limit int) {
	rows, err := t.rows(context.Background(), where)
	if err != nil {
		return
	}
	if order != "" {
		sortRows(rows, order)
	}
	if offset > 0 {
		if offset >= len(rows) {
			rows = nil
		} else {
			rows = rows[offset:]
		}
	}
	if limit > 0 && len(rows) > limit {
		rows = rows[:limit]
	}
	fromRows(rows, dest)
}

func (t *Table) Count(where Filter) int64 {
	if where == nil {
		var count int64
		if err := t.db.sql.QueryRow("SELECT COUNT(*) FROM records WHERE table_name = ?", t.name).Scan(&count); err == nil {
			return count
		}
		return 0
	}
	rows, err := t.rows(context.Background(), where)
	if err != nil {
		return 0
	}
	return int64(len(rows))
}

// CountWhere 按 Filter 计数：可下推条件走 SQL COUNT(*)（命中实体列索引/json_extract），
// 不可下推时回退内存过滤；DB 错误显式返回而不是像 Count 那样吞成 0。
func (t *Table) CountWhere(where Filter) (int64, error) {
	if query, args, ok := filterSQL("SELECT COUNT(*) FROM records WHERE table_name = ?", t.name, where); ok {
		var count int64
		if err := t.db.sql.QueryRow(query, args...).Scan(&count); err != nil {
			return 0, err
		}
		return count, nil
	}
	rows, err := t.rows(context.Background(), where)
	if err != nil {
		return 0, err
	}
	return int64(len(rows)), nil
}

// SumWhere 对 payload 内数值字段求和：可下推条件走 SQL SUM(json_extract(...))，
// 避免整表 JSON 解码（如 Dashboard 用量统计）；不可下推时回退内存求和。
// field 必须来自代码内常量（与 eqFilter 的 json_extract 拼接同一约束）。
func (t *Table) SumWhere(field string, where Filter) (float64, error) {
	expr := fmt.Sprintf("COALESCE(SUM(json_extract(CAST(payload AS TEXT), '$.%s')), 0)", field)
	if query, args, ok := filterSQL("SELECT "+expr+" FROM records WHERE table_name = ?", t.name, where); ok {
		var sum float64
		if err := t.db.sql.QueryRow(query, args...).Scan(&sum); err != nil {
			return 0, err
		}
		return sum, nil
	}
	rows, err := t.rows(context.Background(), where)
	if err != nil {
		return 0, err
	}
	var sum float64
	for _, row := range rows {
		if value, ok := getFloat(row[field]); ok {
			sum += value
		}
	}
	return sum, nil
}

func (t *Table) Delete(id uint) bool {
	result, err := t.db.execWrite("DELETE FROM records WHERE table_name = ? AND id = ?", t.name, id)
	if err != nil {
		return false
	}
	affected, err := result.RowsAffected()
	return err == nil && affected > 0
}

func (t *Table) UpdateWhere(where Filter, updates map[string]interface{}) error {
	_, err := t.UpdateWhereCount(where, updates)
	return err
}

// UpdateWhereCount 同 UpdateWhere，另返回实际更新的行数——条件型更新
// （如 Status=pending 才更新）可据此判定并发赢家：返回 0 表示别的请求已抢先处理。
func (t *Table) UpdateWhereCount(where Filter, updates map[string]interface{}) (int, error) {
	return t.updateRows(context.Background(), where, func(row map[string]interface{}) {
		for key, value := range updates {
			row[key] = value
		}
		row["UpdatedAt"] = time.Now().UTC().Format(time.RFC3339Nano)
	})
}

func (t *Table) All() []map[string]interface{} {
	rows, err := t.rows(context.Background(), nil)
	if err != nil {
		return nil
	}
	return rows
}

func (t *Table) IncrementField(where Filter, field string, delta float64) error {
	_, err := t.updateRows(context.Background(), where, func(row map[string]interface{}) {
		if current, ok := getFloat(row[field]); ok {
			row[field] = current + delta
		}
		row["UpdatedAt"] = time.Now().UTC().Format(time.RFC3339Nano)
	})
	return err
}

func (t *Table) String() string {
	return fmt.Sprintf("Table(%s, %d rows)", t.name, t.Count(nil))
}

func (t *Table) InsertMap(m map[string]interface{}) error {
	copy := cloneMap(m)
	return t.db.WithTx(context.Background(), func(tx *Tx) error {
		id, err := nextID(context.Background(), tx.tx, t.name)
		if err != nil {
			return err
		}
		copy["ID"] = float64(id)
		now := time.Now().UTC().Format(time.RFC3339Nano)
		if _, ok := copy["CreatedAt"]; !ok {
			copy["CreatedAt"] = now
		}
		if _, ok := copy["UpdatedAt"]; !ok {
			copy["UpdatedAt"] = now
		}
		return upsertRecord(context.Background(), tx.tx, t.name, id, copy)
	})
}

func (t *Table) FindByUserIDClientID(userID uint, clientID string) (map[string]interface{}, bool) {
	row, err := fetchOne(context.Background(), t.db.sql,
		"SELECT payload FROM records WHERE table_name = ? AND user_id = ? AND client_id = ?", t.name, userID, clientID)
	return row, err == nil && row != nil
}

func (t *Table) DeleteByUserIDClientID(userID uint, clientID string) bool {
	result, err := t.db.execWrite("DELETE FROM records WHERE table_name = ? AND user_id = ? AND client_id = ?", t.name, userID, clientID)
	if err != nil {
		return false
	}
	affected, err := result.RowsAffected()
	return err == nil && affected > 0
}

// UpdateByUserIDClientID 读-改-写全程放在写事务内：写锁保证 find→upsert 之间
// 没有并发写者插入同名记录或改旧行（此前读在事务外，并发下可能丢更新）。
func (t *Table) UpdateByUserIDClientID(userID uint, clientID string, updates map[string]interface{}) bool {
	updated := false
	err := t.db.WithTx(context.Background(), func(tx *Tx) error {
		row, err := fetchOne(context.Background(), tx.tx,
			"SELECT payload FROM records WHERE table_name = ? AND user_id = ? AND client_id = ?", t.name, userID, clientID)
		if err != nil {
			return err
		}
		if row == nil {
			return nil
		}
		for key, value := range updates {
			row[key] = value
		}
		row["UpdatedAt"] = time.Now().UTC().Format(time.RFC3339Nano)
		id, _ := mapID(row)
		if err := upsertRecord(context.Background(), tx.tx, t.name, id, row); err != nil {
			return err
		}
		updated = true
		return nil
	})
	return err == nil && updated
}

func (t *Table) FindAllByUserID(userID uint) []map[string]interface{} {
	rows, err := fetchRows(context.Background(), t.db.sql,
		"SELECT payload FROM records WHERE table_name = ? AND user_id = ?", t.name, userID)
	if err != nil {
		return nil
	}
	return rows
}

func (t *Table) MaxUpdatedAtByUserID(userID uint) string {
	var value sql.NullString
	err := t.db.sql.QueryRow("SELECT MAX(updated_at) FROM records WHERE table_name = ? AND user_id = ?", t.name, userID).Scan(&value)
	if err != nil || !value.Valid {
		return ""
	}
	return value.String
}

func (t *Table) BatchUpsertByUserIDClientID(userID uint, items []map[string]interface{}) (int, error) {
	upserted := 0
	// 事务错误必须向上传递：吞掉错误会让 handler 在部分失败时仍返回成功，
	// 客户端随即清除本地待同步队列，造成静默数据丢失。
	err := t.db.WithTx(context.Background(), func(tx *Tx) error {
		for _, item := range items {
			clientID := rowClientID(item)
			if clientID == "" {
				continue
			}
			row := cloneMap(item)
			row["UserID"] = userID
			row["ClientID"] = clientID
			id, found, err := findIDByUserClient(context.Background(), tx.tx, t.name, userID, clientID)
			if err != nil {
				return err
			}
			if found {
				existing, err := fetchOne(context.Background(), tx.tx, "SELECT payload FROM records WHERE table_name = ? AND id = ?", t.name, id)
				if err != nil {
					return err
				}
				for key, value := range row {
					existing[key] = value
				}
				row = existing
			} else {
				id, err = nextID(context.Background(), tx.tx, t.name)
				if err != nil {
					return err
				}
				row["ID"] = float64(id)
				if _, ok := row["CreatedAt"]; !ok {
					row["CreatedAt"] = time.Now().UTC().Format(time.RFC3339Nano)
				}
			}
			row["UpdatedAt"] = time.Now().UTC().Format(time.RFC3339Nano)
			if err := upsertRecord(context.Background(), tx.tx, t.name, id, row); err != nil {
				return err
			}
			upserted++
		}
		return nil
	})
	return upserted, err
}

// DeleteWhereRaw 按原生 SQL 条件批量删除（仅供保留策略等维护任务使用，
// cond 必须是代码内常量，参数走占位符）
func (t *Table) DeleteWhereRaw(cond string, args ...interface{}) (int64, error) {
	query := "DELETE FROM records WHERE table_name = ? AND " + cond
	result, err := t.db.execWrite(query, append([]interface{}{t.name}, args...)...)
	if err != nil {
		return 0, err
	}
	return result.RowsAffected()
}

func (t *Table) BatchDeleteByUserIDClientID(userID uint, clientIDs []string) int {
	if len(clientIDs) == 0 {
		return 0
	}
	placeholders := strings.TrimRight(strings.Repeat("?,", len(clientIDs)), ",")
	args := make([]interface{}, 0, len(clientIDs)+2)
	args = append(args, t.name, userID)
	for _, clientID := range clientIDs {
		args = append(args, clientID)
	}
	result, err := t.db.execWrite("DELETE FROM records WHERE table_name = ? AND user_id = ? AND client_id IN ("+placeholders+")", args...)
	if err != nil {
		return 0
	}
	affected, _ := result.RowsAffected()
	return int(affected)
}

func (t *Table) BatchInsertMaps(rows []map[string]interface{}) (int, error) {
	inserted := 0
	err := t.db.WithTx(context.Background(), func(tx *Tx) error {
		for _, item := range rows {
			id, err := nextID(context.Background(), tx.tx, t.name)
			if err != nil {
				return err
			}
			row := cloneMap(item)
			row["ID"] = float64(id)
			now := time.Now().UTC().Format(time.RFC3339Nano)
			if _, ok := row["CreatedAt"]; !ok {
				row["CreatedAt"] = now
			}
			if _, ok := row["UpdatedAt"]; !ok {
				row["UpdatedAt"] = now
			}
			if err := upsertRecord(context.Background(), tx.tx, t.name, id, row); err != nil {
				return err
			}
			inserted++
		}
		return nil
	})
	return inserted, err
}

func (t *Table) rows(ctx context.Context, where Filter) ([]map[string]interface{}, error) {
	// 可下推的过滤在 SQL 侧完成，避免整表 JSON 解码（热路径：登录/计费/同步中间件）
	if query, args, ok := filterSQL("SELECT payload FROM records WHERE table_name = ?", t.name, where); ok {
		return fetchRows(ctx, t.db.sql, query, args...)
	}
	rows, err := fetchRows(ctx, t.db.sql, "SELECT payload FROM records WHERE table_name = ?", t.name)
	if err != nil {
		return rows, err
	}
	filtered := rows[:0]
	for _, row := range rows {
		if where.Match(row) {
			filtered = append(filtered, row)
		}
	}
	return filtered, nil
}

func (t *Table) updateRows(ctx context.Context, where Filter, mutate func(map[string]interface{})) (int, error) {
	mutated := 0
	err := t.db.WithTx(ctx, func(tx *Tx) error {
		query, args, pushdown := filterSQL("SELECT payload FROM records WHERE table_name = ?", t.name, where)
		if !pushdown {
			query, args = "SELECT payload FROM records WHERE table_name = ?", []interface{}{t.name}
		}
		rows, err := fetchRows(ctx, tx.tx, query, args...)
		if err != nil {
			return err
		}
		for _, row := range rows {
			if !pushdown && where != nil && !where.Match(row) {
				continue
			}
			mutate(row)
			id, ok := mapID(row)
			if !ok {
				return errors.New("记录缺少 ID")
			}
			if err := upsertRecord(ctx, tx.tx, t.name, id, row); err != nil {
				return err
			}
			mutated++
		}
		return nil
	})
	return mutated, err
}

// Filter 行过滤器。Match 提供内存判定；toSQL 尝试把条件下推为 SQL
// （payload 是 JSON 文本，等值条件用 json_extract 在 SQL 侧过滤），
// 避免热路径把整表读进 Go 逐行反序列化。ok=false 时调用方回退内存过滤。
type Filter interface {
	Match(row map[string]interface{}) bool
	toSQL() (cond string, args []interface{}, ok bool)
}

// funcFilter 普通闭包适配器：只做内存过滤，不可下推。
type funcFilter func(map[string]interface{}) bool

func (f funcFilter) Match(row map[string]interface{}) bool { return f(row) }
func (f funcFilter) toSQL() (string, []interface{}, bool) { return "", nil, false }

// FilterFunc 把普通判定函数适配为 Filter（走内存过滤，不下推）。
func FilterFunc(f func(map[string]interface{}) bool) Filter { return funcFilter(f) }

// entityColumns 是 records 实体列与 payload 字段的镜像映射（upsertRecord 写入时同步维护），
// 等值过滤可直接命中 idx_records_* 索引。
var entityColumns = map[string]string{
	"ID":       "id",
	"UserID":   "user_id",
	"ClientID": "client_id",
	"OrderNo":  "order_no",
	"Status":   "status",
}

// normalizeSQLArg 把 Go 值规整为 SQLite 可比较的类型（bool→0/1，整型→int64）。
func normalizeSQLArg(value interface{}) interface{} {
	switch v := value.(type) {
	case bool:
		if v {
			return int64(1)
		}
		return int64(0)
	case int:
		return int64(v)
	case int8:
		return int64(v)
	case int16:
		return int64(v)
	case int32:
		return int64(v)
	case int64:
		return v
	case uint:
		return int64(v)
	case uint8:
		return int64(v)
	case uint16:
		return int64(v)
	case uint32:
		return int64(v)
	case uint64:
		return int64(v)
	}
	return value
}

// eqFilter 等值过滤：可整体下推。
type eqFilter struct {
	field string
	value interface{}
}

func (f eqFilter) Match(row map[string]interface{}) bool {
	return fmt.Sprintf("%v", row[f.field]) == fmt.Sprintf("%v", f.value)
}

func (f eqFilter) toSQL() (string, []interface{}, bool) {
	// 命中实体列镜像时直接走索引列
	if col, ok := entityColumns[f.field]; ok {
		return col + " = ?", []interface{}{normalizeSQLArg(f.value)}, true
	}
	// payload JSON 字段：精确匹配，或文本化后再匹配——两条合起来对齐
	// Match 的 fmt.Sprintf("%v") 字符串比较语义（JSON 数字 5 与参数 "5"/5 都能匹配，
	// JSON true 与参数 true/"true" 分别命中精确/文本分支）。
	// field 全部来自代码内字符串常量，不存在注入面。
	expr := fmt.Sprintf("json_extract(CAST(payload AS TEXT), '$.%s')", f.field)
	return "(" + expr + " = ? OR CAST(" + expr + " AS TEXT) = ?)",
		[]interface{}{normalizeSQLArg(f.value), fmt.Sprintf("%v", f.value)}, true
}

func FilterEq(field string, value interface{}) Filter {
	return eqFilter{field: field, value: value}
}

func FilterLike(field, pattern string) Filter {
	needle := strings.ToLower(strings.ReplaceAll(pattern, "%", ""))
	return funcFilter(func(row map[string]interface{}) bool {
		return strings.Contains(strings.ToLower(fmt.Sprintf("%v", row[field])), needle)
	})
}

func FilterGte(field string, value interface{}) Filter {
	want := fmt.Sprintf("%v", value)
	return funcFilter(func(row map[string]interface{}) bool { return fmt.Sprintf("%v", row[field]) >= want })
}

// dateFilter 日期前缀过滤：日期串为纯数字+横线（无 LIKE 通配符），可安全下推为前缀 LIKE
type dateFilter struct {
	field string
	date  string
}

func (f dateFilter) Match(row map[string]interface{}) bool {
	return strings.HasPrefix(fmt.Sprintf("%v", row[f.field]), f.date)
}

func (f dateFilter) toSQL() (string, []interface{}, bool) {
	expr := fmt.Sprintf("CAST(json_extract(CAST(payload AS TEXT), '$.%s') AS TEXT)", f.field)
	return expr + " LIKE ?", []interface{}{f.date + "%"}, true
}

func FilterDate(field, date string) Filter {
	return dateFilter{field: field, date: date}
}

// orFilter/orFilter 组合过滤：子条件全部可下推时才整体下推。
type orFilter struct{ parts []Filter }

func (f orFilter) Match(row map[string]interface{}) bool {
	for _, part := range f.parts {
		if part != nil && part.Match(row) {
			return true
		}
	}
	return false
}

func (f orFilter) toSQL() (string, []interface{}, bool) {
	var conds []string
	var args []interface{}
	for _, part := range f.parts {
		if part == nil {
			continue
		}
		cond, partArgs, ok := part.toSQL()
		if !ok {
			return "", nil, false
		}
		conds = append(conds, "("+cond+")")
		args = append(args, partArgs...)
	}
	if len(conds) == 0 {
		return "", nil, false
	}
	return strings.Join(conds, " OR "), args, true
}

func FilterOr(first, second Filter) Filter {
	return orFilter{parts: []Filter{first, second}}
}

type andFilter struct{ parts []Filter }

func (f andFilter) Match(row map[string]interface{}) bool {
	for _, part := range f.parts {
		if part != nil && !part.Match(row) {
			return false
		}
	}
	return true
}

func (f andFilter) toSQL() (string, []interface{}, bool) {
	var conds []string
	var args []interface{}
	for _, part := range f.parts {
		if part == nil {
			continue
		}
		cond, partArgs, ok := part.toSQL()
		if !ok {
			return "", nil, false
		}
		conds = append(conds, "("+cond+")")
		args = append(args, partArgs...)
	}
	if len(conds) == 0 {
		return "", nil, false
	}
	return strings.Join(conds, " AND "), args, true
}

func FilterAnd(first, second Filter) Filter {
	return andFilter{parts: []Filter{first, second}}
}

func FilterAll(filters ...Filter) Filter {
	return andFilter{parts: filters}
}

// filterSQL 生成带下推条件的查询；where 不可下推时返回 ok=false，调用方需内存回退。
func filterSQL(base string, tableName string, where Filter) (string, []interface{}, bool) {
	if where == nil {
		return base, []interface{}{tableName}, true
	}
	cond, args, ok := where.toSQL()
	if !ok {
		return "", nil, false
	}
	return base + " AND " + cond, append([]interface{}{tableName}, args...), true
}

type sqlQueryer interface {
	QueryContext(context.Context, string, ...interface{}) (*sql.Rows, error)
	QueryRowContext(context.Context, string, ...interface{}) *sql.Row
}

type sqlExecer interface {
	ExecContext(context.Context, string, ...interface{}) (sql.Result, error)
}

func fetchOne(ctx context.Context, queryer sqlQueryer, query string, args ...interface{}) (map[string]interface{}, error) {
	var payload []byte
	err := queryer.QueryRowContext(ctx, query, args...).Scan(&payload)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return decodeRow(payload)
}

func fetchRows(ctx context.Context, queryer sqlQueryer, query string, args ...interface{}) ([]map[string]interface{}, error) {
	result, err := queryer.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer result.Close()
	var rows []map[string]interface{}
	for result.Next() {
		var payload []byte
		if err := result.Scan(&payload); err != nil {
			return nil, err
		}
		row, err := decodeRow(payload)
		if err != nil {
			return nil, err
		}
		rows = append(rows, row)
	}
	return rows, result.Err()
}

func decodeRow(payload []byte) (map[string]interface{}, error) {
	var row map[string]interface{}
	if err := json.Unmarshal(payload, &row); err != nil {
		return nil, fmt.Errorf("解析 SQLite 记录失败: %w", err)
	}
	return row, nil
}

func upsertRecord(ctx context.Context, execer sqlExecer, tableName string, id uint, row map[string]interface{}) error {
	payload, err := json.Marshal(row)
	if err != nil {
		return err
	}
	userID, _ := mapUint(row["UserID"])
	if userID == 0 {
		userID, _ = mapUint(row["user_id"])
	}
	clientID := rowClientID(row)
	orderNo := mapString(row["OrderNo"])
	status := mapString(row["Status"])
	updatedAt := mapString(row["UpdatedAt"])
	_, err = execer.ExecContext(ctx, `INSERT INTO records(table_name, id, payload, user_id, client_id, order_no, status, updated_at)
		VALUES(?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(table_name, id) DO UPDATE SET payload=excluded.payload, user_id=excluded.user_id,
		client_id=excluded.client_id, order_no=excluded.order_no, status=excluded.status, updated_at=excluded.updated_at`,
		tableName, id, payload, nullableUint(userID), nullableString(clientID), nullableString(orderNo), nullableString(status), nullableString(updatedAt))
	return err
}

func nextID(ctx context.Context, tx *sql.Tx, tableName string) (uint, error) {
	var sequence uint
	err := tx.QueryRowContext(ctx, "SELECT seq FROM table_sequences WHERE table_name = ?", tableName).Scan(&sequence)
	if errors.Is(err, sql.ErrNoRows) {
		sequence = 0
		if _, err := tx.ExecContext(ctx, "INSERT INTO table_sequences(table_name, seq) VALUES(?, 0)", tableName); err != nil {
			return 0, err
		}
	} else if err != nil {
		return 0, err
	}
	sequence++
	if _, err := tx.ExecContext(ctx, "UPDATE table_sequences SET seq = ? WHERE table_name = ?", sequence, tableName); err != nil {
		return 0, err
	}
	return sequence, nil
}

func findIDByUserClient(ctx context.Context, tx *sql.Tx, tableName string, userID uint, clientID string) (uint, bool, error) {
	var id uint
	err := tx.QueryRowContext(ctx, "SELECT id FROM records WHERE table_name = ? AND user_id = ? AND client_id = ?", tableName, userID, clientID).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, false, nil
	}
	return id, err == nil, err
}

func mapID(row map[string]interface{}) (uint, bool) { return mapUint(row["ID"]) }

func mapUint(value interface{}) (uint, bool) {
	if number, ok := getFloat(value); ok && number >= 0 {
		return uint(number), true
	}
	return 0, false
}

func mapString(value interface{}) string {
	if value == nil {
		return ""
	}
	return fmt.Sprintf("%v", value)
}

func nullableUint(value uint) interface{} {
	if value == 0 {
		return nil
	}
	return value
}

func nullableString(value string) interface{} {
	if value == "" {
		return nil
	}
	return value
}

func rowClientID(row map[string]interface{}) string {
	if value, ok := row["ClientID"].(string); ok {
		return value
	}
	if value, ok := row["client_id"].(string); ok {
		return value
	}
	return ""
}

func cloneMap(row map[string]interface{}) map[string]interface{} {
	copy := make(map[string]interface{}, len(row))
	for key, value := range row {
		copy[key] = value
	}
	return copy
}

func sortRows(rows []map[string]interface{}, order string) {
	parts := strings.Fields(order)
	if len(parts) == 0 {
		return
	}
	field := parts[0]
	descending := len(parts) > 1 && strings.EqualFold(parts[1], "DESC")
	sort.SliceStable(rows, func(left, right int) bool {
		// 两侧均为数值时按数值比较：纯字符串比较会让 "10" < "9"，
		// version_code 到达 100 时更新检查会把旧版错当最新版下发。
		if firstNum, ok := getFloat(rows[left][field]); ok {
			if secondNum, ok2 := getFloat(rows[right][field]); ok2 {
				if descending {
					return firstNum > secondNum
				}
				return firstNum < secondNum
			}
		}
		first := fmt.Sprintf("%v", rows[left][field])
		second := fmt.Sprintf("%v", rows[right][field])
		if descending {
			return first > second
		}
		return first < second
	})
}

func toMap(value interface{}) map[string]interface{} {
	rv := reflect.ValueOf(value)
	if rv.Kind() == reflect.Ptr {
		rv = rv.Elem()
	}
	rt := rv.Type()
	row := make(map[string]interface{})
	for index := 0; index < rt.NumField(); index++ {
		field := rt.Field(index)
		fieldValue := rv.Field(index)
		if !fieldValue.CanInterface() {
			continue
		}
		if timestamp, ok := fieldValue.Interface().(time.Time); ok {
			row[field.Name] = timestamp.UTC().Format(time.RFC3339Nano)
		} else {
			row[field.Name] = fieldValue.Interface()
		}
	}
	return row
}

func fromRows(rows []map[string]interface{}, dest interface{}) {
	rv := reflect.ValueOf(dest)
	if rv.Kind() != reflect.Ptr || rv.Elem().Kind() != reflect.Slice {
		return
	}
	slice := rv.Elem()
	elementType := slice.Type().Elem()
	result := reflect.MakeSlice(slice.Type(), len(rows), len(rows))
	for index, row := range rows {
		if elementType.Kind() == reflect.Ptr {
			element := reflect.New(elementType.Elem())
			fromMap(row, element.Interface())
			result.Index(index).Set(element)
			continue
		}
		// map 元素直接赋值（fromMap 只处理 struct；此前 []map 目标静默产出 nil 行）
		if elementType.Kind() == reflect.Map {
			result.Index(index).Set(reflect.ValueOf(row))
			continue
		}
		element := reflect.New(elementType)
		fromMap(row, element.Interface())
		result.Index(index).Set(element.Elem())
	}
	slice.Set(result)
}

func fromMap(row map[string]interface{}, dest interface{}) {
	rv := reflect.ValueOf(dest)
	if rv.Kind() != reflect.Ptr || rv.Elem().Kind() != reflect.Struct {
		return
	}
	rv = rv.Elem()
	rt := rv.Type()
	for index := 0; index < rt.NumField(); index++ {
		field := rt.Field(index)
		value := rv.Field(index)
		if !value.CanSet() {
			continue
		}
		mapValue, ok := row[field.Name]
		if !ok || mapValue == nil {
			continue
		}
		switch value.Kind() {
		case reflect.String:
			value.SetString(fmt.Sprintf("%v", mapValue))
		case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
			if number, ok := getFloat(mapValue); ok {
				value.SetInt(int64(number))
			}
		case reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64:
			if number, ok := getFloat(mapValue); ok {
				value.SetUint(uint64(number))
			}
		case reflect.Float32, reflect.Float64:
			if number, ok := getFloat(mapValue); ok {
				value.SetFloat(number)
			}
		case reflect.Bool:
			if boolean, ok := mapValue.(bool); ok {
				value.SetBool(boolean)
			}
		case reflect.Slice:
			encoded, err := json.Marshal(mapValue)
			if err == nil {
				_ = json.Unmarshal(encoded, value.Addr().Interface())
			}
		case reflect.Struct:
			if field.Type == reflect.TypeOf(time.Time{}) {
				if timestamp, err := time.Parse(time.RFC3339Nano, fmt.Sprintf("%v", mapValue)); err == nil {
					value.Set(reflect.ValueOf(timestamp))
				}
			}
		case reflect.Ptr:
			switch field.Type {
			case reflect.TypeOf((*uint)(nil)):
				if number, ok := getFloat(mapValue); ok {
					result := uint(number)
					value.Set(reflect.ValueOf(&result))
				}
			case reflect.TypeOf((*time.Time)(nil)):
				if timestamp, err := time.Parse(time.RFC3339Nano, fmt.Sprintf("%v", mapValue)); err == nil {
					value.Set(reflect.ValueOf(&timestamp))
				}
			case reflect.TypeOf((*bool)(nil)):
				if boolean, ok := mapValue.(bool); ok {
					value.Set(reflect.ValueOf(&boolean))
				}
			}
		}
	}
}

func getFloat(value interface{}) (float64, bool) {
	switch number := value.(type) {
	case float64:
		return number, true
	case float32:
		return float64(number), true
	case int:
		return float64(number), true
	case int64:
		return float64(number), true
	case uint:
		return float64(number), true
	case json.Number:
		parsed, err := number.Float64()
		return parsed, err == nil
	}
	return 0, false
}

func setStructField(object interface{}, name string, value interface{}) {
	rv := reflect.ValueOf(object)
	if rv.Kind() == reflect.Ptr {
		rv = rv.Elem()
	}
	field := rv.FieldByName(name)
	if field.IsValid() && field.CanSet() {
		if number, ok := value.(uint); ok {
			field.SetUint(uint64(number))
		}
	}
}

func TableName(model interface{}) string {
	typeOf := reflect.TypeOf(model)
	if typeOf.Kind() == reflect.Ptr {
		typeOf = typeOf.Elem()
	}
	return typeOf.Name()
}
