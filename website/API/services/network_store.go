package services

import (
	"aichat-api/database"
	"aichat-api/models"
)

// network_store.go — NetworkAgent / NetworkGroup 表数据访问薄封装，供 handlers 层使用。
// 列表查询的组合过滤（FilterEq/FilterLike/filterAny）在此构建，handlers 不再接触 database.Filter。

// filterAny 返回一个 Filter，当传入的任一 filter 匹配时即返回 true（逻辑 OR）。
// database 包只提供 FilterOr(f1, f2) 两元版本，此辅助函数支持任意数量。
// 裸闭包经 database.FilterFunc 适配，走内存过滤（不下推 SQL）。
func filterAny(filters ...database.Filter) database.Filter {
	return database.FilterFunc(func(m map[string]interface{}) bool {
		for _, f := range filters {
			if f != nil && f.Match(m) {
				return true
			}
		}
		return false
	})
}

// networkReviewStatuses 网络市场内容的全部状态枚举。
var networkReviewStatuses = []string{"pending", "approved", "rejected", "taken_down"}

// NetworkAgentStatusCounts 统计 NetworkAgent 各状态记录数（COUNT 下推 SQL）。
func NetworkAgentStatusCounts() (map[string]int64, error) {
	tbl := database.Get().Register("NetworkAgent")
	counts := make(map[string]int64, len(networkReviewStatuses))
	for _, status := range networkReviewStatuses {
		n, err := tbl.CountWhere(database.FilterEq("Status", status))
		if err != nil {
			return nil, err
		}
		counts[status] = n
	}
	return counts, nil
}

// NetworkGroupStatusCounts 统计 NetworkGroup 各状态记录数（COUNT 下推 SQL）。
func NetworkGroupStatusCounts() (map[string]int64, error) {
	tbl := database.Get().Register("NetworkGroup")
	counts := make(map[string]int64, len(networkReviewStatuses))
	for _, status := range networkReviewStatuses {
		n, err := tbl.CountWhere(database.FilterEq("Status", status))
		if err != nil {
			return nil, err
		}
		counts[status] = n
	}
	return counts, nil
}

// AdminSearchNetworkAgents 管理端智能体列表：按状态精确匹配 + 名称/上传者模糊搜索，
// 返回分页结果与总数（CreatedAt desc）。
func AdminSearchNetworkAgents(status, query string, offset, limit int) ([]models.NetworkAgent, int64, error) {
	filters := []database.Filter{}
	if status != "" {
		filters = append(filters, database.FilterEq("Status", status))
	}
	if query != "" {
		filters = append(filters, filterAny(
			database.FilterLike("Name", query),
			database.FilterLike("UploaderName", query),
		))
	}
	var combined database.Filter
	if len(filters) > 0 {
		combined = database.FilterAll(filters...)
	}

	tbl := database.Get().Register("NetworkAgent")
	total, err := tbl.CountWhere(combined)
	if err != nil {
		return nil, 0, err
	}
	var agents []models.NetworkAgent
	tbl.FindAll(&agents, combined, "CreatedAt desc", offset, limit)
	return agents, total, nil
}

// AdminSearchNetworkGroups 管理端群聊列表：语义同 AdminSearchNetworkAgents。
func AdminSearchNetworkGroups(status, query string, offset, limit int) ([]models.NetworkGroup, int64, error) {
	filters := []database.Filter{}
	if status != "" {
		filters = append(filters, database.FilterEq("Status", status))
	}
	if query != "" {
		filters = append(filters, filterAny(
			database.FilterLike("Name", query),
			database.FilterLike("UploaderName", query),
		))
	}
	var combined database.Filter
	if len(filters) > 0 {
		combined = database.FilterAll(filters...)
	}

	tbl := database.Get().Register("NetworkGroup")
	total, err := tbl.CountWhere(combined)
	if err != nil {
		return nil, 0, err
	}
	var groups []models.NetworkGroup
	tbl.FindAll(&groups, combined, "CreatedAt desc", offset, limit)
	return groups, total, nil
}

// PublicSearchNetworkAgents 公开市场智能体列表：仅 approved，支持关键词
// （名称/描述/标签任一命中）与标签筛选（任一命中），order 由调用方给定。
func PublicSearchNetworkAgents(query string, tags []string, order string, offset, limit int) ([]models.NetworkAgent, int64, error) {
	filters := []database.Filter{database.FilterEq("Status", "approved")}
	if query != "" {
		filters = append(filters, filterAny(
			database.FilterLike("Name", query),
			database.FilterLike("Description", query),
			database.FilterLike("Tags", query),
		))
	}
	if len(tags) > 0 {
		tagFilters := make([]database.Filter, 0, len(tags))
		for _, t := range tags {
			tagFilters = append(tagFilters, database.FilterLike("Tags", "\""+t+"\""))
		}
		filters = append(filters, filterAny(tagFilters...))
	}
	combined := database.FilterAll(filters...)

	tbl := database.Get().Register("NetworkAgent")
	total, err := tbl.CountWhere(combined)
	if err != nil {
		return nil, 0, err
	}
	var agents []models.NetworkAgent
	tbl.FindAll(&agents, combined, order, offset, limit)
	return agents, total, nil
}

// PublicSearchNetworkGroups 公开市场群聊列表：语义同 PublicSearchNetworkAgents。
func PublicSearchNetworkGroups(query string, tags []string, order string, offset, limit int) ([]models.NetworkGroup, int64, error) {
	filters := []database.Filter{database.FilterEq("Status", "approved")}
	if query != "" {
		filters = append(filters, filterAny(
			database.FilterLike("Name", query),
			database.FilterLike("Description", query),
			database.FilterLike("Tags", query),
		))
	}
	if len(tags) > 0 {
		tagFilters := make([]database.Filter, 0, len(tags))
		for _, t := range tags {
			tagFilters = append(tagFilters, database.FilterLike("Tags", "\""+t+"\""))
		}
		filters = append(filters, filterAny(tagFilters...))
	}
	combined := database.FilterAll(filters...)

	tbl := database.Get().Register("NetworkGroup")
	total, err := tbl.CountWhere(combined)
	if err != nil {
		return nil, 0, err
	}
	var groups []models.NetworkGroup
	tbl.FindAll(&groups, combined, order, offset, limit)
	return groups, total, nil
}

// FindNetworkAgentByID 按主键查网络智能体；未找到返回 (nil, nil)。
func FindNetworkAgentByID(id uint) (*models.NetworkAgent, error) {
	var agent models.NetworkAgent
	found, err := database.Get().Register("NetworkAgent").FindByIDE(id, &agent)
	if err != nil || !found {
		return nil, err
	}
	return &agent, nil
}

// FindNetworkGroupByID 按主键查网络群聊；未找到返回 (nil, nil)。
func FindNetworkGroupByID(id uint) (*models.NetworkGroup, error) {
	var group models.NetworkGroup
	found, err := database.Get().Register("NetworkGroup").FindByIDE(id, &group)
	if err != nil || !found {
		return nil, err
	}
	return &group, nil
}

// ListNetworkAgentsByUploader 列出上传者的全部智能体（UpdatedAt desc）。
func ListNetworkAgentsByUploader(userID uint) []models.NetworkAgent {
	var agents []models.NetworkAgent
	database.Get().Register("NetworkAgent").FindAll(&agents, database.FilterEq("UploaderID", userID), "UpdatedAt desc", 0, 0)
	return agents
}

// ListNetworkGroupsByUploader 列出上传者的全部群聊（UpdatedAt desc）。
func ListNetworkGroupsByUploader(userID uint) []models.NetworkGroup {
	var groups []models.NetworkGroup
	database.Get().Register("NetworkGroup").FindAll(&groups, database.FilterEq("UploaderID", userID), "UpdatedAt desc", 0, 0)
	return groups
}

// InsertNetworkAgent 新建网络智能体。
func InsertNetworkAgent(agent *models.NetworkAgent) error {
	return database.Get().Register("NetworkAgent").Insert(agent)
}

// InsertNetworkGroup 新建网络群聊。
func InsertNetworkGroup(group *models.NetworkGroup) error {
	return database.Get().Register("NetworkGroup").Insert(group)
}

// UpdateNetworkAgentByID 按主键更新网络智能体字段。
func UpdateNetworkAgentByID(id uint, updates map[string]interface{}) error {
	return database.Get().Register("NetworkAgent").UpdateWhere(database.FilterEq("ID", id), updates)
}

// UpdateNetworkGroupByID 按主键更新网络群聊字段。
func UpdateNetworkGroupByID(id uint, updates map[string]interface{}) error {
	return database.Get().Register("NetworkGroup").UpdateWhere(database.FilterEq("ID", id), updates)
}

// UpdatePendingNetworkAgentVersion 仅当记录仍处于指定版本且 pending 状态时更新，
// 供异步 AI 预审写回，防止与人工审核/并发编辑互相覆盖。
func UpdatePendingNetworkAgentVersion(id uint, version int, updates map[string]interface{}) error {
	return database.Get().Register("NetworkAgent").UpdateWhere(
		database.FilterAll(
			database.FilterEq("ID", id),
			database.FilterEq("Version", version),
			database.FilterEq("Status", "pending"),
		),
		updates,
	)
}

// UpdatePendingNetworkGroupVersion 群聊侧语义同 UpdatePendingNetworkAgentVersion。
func UpdatePendingNetworkGroupVersion(id uint, version int, updates map[string]interface{}) error {
	return database.Get().Register("NetworkGroup").UpdateWhere(
		database.FilterAll(
			database.FilterEq("ID", id),
			database.FilterEq("Version", version),
			database.FilterEq("Status", "pending"),
		),
		updates,
	)
}

// DeleteNetworkAgentByID 按主键物理删除网络智能体；返回是否实际删除。
func DeleteNetworkAgentByID(id uint) bool {
	return database.Get().Register("NetworkAgent").Delete(id)
}

// DeleteNetworkGroupByID 按主键物理删除网络群聊；返回是否实际删除。
func DeleteNetworkGroupByID(id uint) bool {
	return database.Get().Register("NetworkGroup").Delete(id)
}

// IncrementNetworkAgentDownloads 原子自增智能体下载量。
func IncrementNetworkAgentDownloads(id uint) error {
	return database.Get().Register("NetworkAgent").IncrementField(database.FilterEq("ID", id), "DownloadCount", 1)
}

// IncrementNetworkGroupDownloads 原子自增群聊下载量。
func IncrementNetworkGroupDownloads(id uint) error {
	return database.Get().Register("NetworkGroup").IncrementField(database.FilterEq("ID", id), "DownloadCount", 1)
}
