package services

import (
	"errors"

	"aichat-api/database"
	"aichat-api/models"
)

var ErrAgentNotOwned = errors.New("智能体不属于当前账号")

// agent_store.go — UserAgent 表数据访问薄封装，供 handlers 层使用。

// ListUserAgentsByUser 列出用户全部智能体（UpdatedAt desc，UserID 走索引下推）。
func ListUserAgentsByUser(userID uint) []models.UserAgent {
	var agents []models.UserAgent
	database.Get().Register("UserAgent").FindAll(&agents, database.FilterEq("UserID", userID), "UpdatedAt desc", 0, 0)
	return agents
}

// FindUserAgentByID 按主键查用户智能体；未找到返回 (nil, nil)。
func FindUserAgentByID(id uint) (*models.UserAgent, error) {
	var agent models.UserAgent
	found, err := database.Get().Register("UserAgent").FindByIDE(id, &agent)
	if err != nil || !found {
		return nil, err
	}
	return &agent, nil
}

// FindUserAgentByClientID resolves the client-generated stable identity within
// an account. An empty client ID is never a valid ownership lookup.
func FindUserAgentByClientID(userID uint, clientID string) (*models.UserAgent, error) {
	if userID == 0 || clientID == "" {
		return nil, ErrAgentNotOwned
	}
	var agent models.UserAgent
	found, err := database.Get().Register("UserAgent").FindOneE(
		database.FilterAnd(
			database.FilterEq("UserID", userID),
			database.FilterEq("ClientID", clientID),
		),
		&agent,
	)
	if err != nil {
		return nil, err
	}
	if !found {
		return nil, ErrAgentNotOwned
	}
	return &agent, nil
}

// RequireOwnedAgent is the single authorization boundary for client agent IDs.
func RequireOwnedAgent(userID uint, clientID string) (*models.UserAgent, error) {
	return FindUserAgentByClientID(userID, clientID)
}

// InsertUserAgent 新建用户智能体。
func InsertUserAgent(agent *models.UserAgent) error {
	return database.Get().Register("UserAgent").Insert(agent)
}

// UpdateUserAgentByID 按主键更新用户智能体字段。
func UpdateUserAgentByID(id uint, updates map[string]interface{}) error {
	return database.Get().Register("UserAgent").UpdateWhere(database.FilterEq("ID", id), updates)
}

// DeleteUserAgentByID 按主键删除用户智能体；返回是否实际删除。
func DeleteUserAgentByID(id uint) bool {
	return database.Get().Register("UserAgent").Delete(id)
}
