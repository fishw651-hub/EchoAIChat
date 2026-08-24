package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"aichat-api/database"
	"aichat-api/models"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

func TestPlanHandler_CreatePlanPersistsAllowSync(t *testing.T) {
	gin.SetMode(gin.TestMode)
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("init database: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})

	router := gin.New()
	handler := &PlanHandler{}
	router.POST("/plans", handler.CreatePlan)

	body := bytes.NewBufferString(`{
		"name": "Sync Plan",
		"price": 9.9,
		"daily_quota": 1,
		"duration_days": 30,
		"allow_sync": true
	}`)
	req := httptest.NewRequest(http.MethodPost, "/plans", body)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	router.ServeHTTP(rec, req)

	var resp utils.Response
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("response code = %d, want %d; body=%s", resp.Code, utils.CodeSuccess, rec.Body.String())
	}

	var plans []models.SubscriptionPlan
	database.Get().Register("SubscriptionPlan").FindAll(&plans, nil, "", 0, 0)
	if len(plans) != 1 {
		t.Fatalf("stored plans = %d, want 1", len(plans))
	}
	if !plans[0].AllowSync {
		t.Fatalf("AllowSync = false, want true")
	}
}

func TestPlanHandler_UpdatePlanPersistsAllowSync(t *testing.T) {
	gin.SetMode(gin.TestMode)
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("init database: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})

	plan := models.SubscriptionPlan{
		Name:         "Basic",
		Price:        1,
		DurationDays: 30,
		Status:       1,
	}
	if err := database.Get().Register("SubscriptionPlan").Insert(&plan); err != nil {
		t.Fatalf("insert plan: %v", err)
	}

	router := gin.New()
	handler := &PlanHandler{}
	router.PUT("/plans/:id", handler.UpdatePlan)

	req := httptest.NewRequest(http.MethodPut, "/plans/1", bytes.NewBufferString(`{"allow_sync": true}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	router.ServeHTTP(rec, req)

	var resp utils.Response
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("response code = %d, want %d; body=%s", resp.Code, utils.CodeSuccess, rec.Body.String())
	}

	var updated models.SubscriptionPlan
	if !database.Get().Register("SubscriptionPlan").FindByID(plan.ID, &updated) {
		t.Fatal("updated plan not found")
	}
	if !updated.AllowSync {
		t.Fatalf("AllowSync = false, want true")
	}
}
