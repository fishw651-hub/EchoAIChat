package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"aichat-api/database"
	"aichat-api/models"

	"github.com/gin-gonic/gin"
)

func TestListMyReviewStatusesReturnsOnlyCurrentUsersReasons(t *testing.T) {
	setupAiReviewTestDB(t)
	now := time.Now().UTC()
	agent := models.NetworkAgent{
		UploaderID:   7,
		Name:         "被拒绝的智能体",
		Status:       "rejected",
		RejectReason: "人设包含违规内容",
		Version:      2,
		ReviewedAt:   &now,
	}
	if err := database.Get().Register("NetworkAgent").Insert(&agent); err != nil {
		t.Fatal(err)
	}
	otherGroup := models.NetworkGroup{
		UploaderID:   8,
		Name:         "别人的群聊",
		Status:       "rejected",
		RejectReason: "不得泄漏",
		Version:      1,
	}
	if err := database.Get().Register("NetworkGroup").Insert(&otherGroup); err != nil {
		t.Fatal(err)
	}

	router := gin.New()
	router.GET("/statuses", func(c *gin.Context) {
		c.Set("user_id", uint(7))
		(&NetworkAgentHandler{}).ListMyReviewStatuses(c)
	})
	recorder := httptest.NewRecorder()
	router.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/statuses", nil))
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, body=%s", recorder.Code, recorder.Body.String())
	}

	var response struct {
		Data []struct {
			ResourceType string     `json:"resource_type"`
			ID           uint       `json:"id"`
			Name         string     `json:"name"`
			Status       string     `json:"status"`
			RejectReason string     `json:"reject_reason"`
			Version      int        `json:"version"`
			ReviewedAt   *time.Time `json:"reviewed_at"`
		} `json:"data"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	if len(response.Data) != 1 {
		t.Fatalf("statuses = %#v, want one current-user result", response.Data)
	}
	got := response.Data[0]
	if got.ResourceType != "agent" || got.ID != agent.ID ||
		got.RejectReason != agent.RejectReason || got.ReviewedAt == nil {
		t.Fatalf("status = %#v", got)
	}
}
