package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"aichat-api/database"
	"aichat-api/models"

	"github.com/gin-gonic/gin"
)

func TestCheckModelAllowedDoesNotRestrictEnabledProNamedModel(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})
	if err := database.Get().Register("ModelPrice").Insert(&models.ModelPrice{
		ModelID:        "deepseek-v4-pro",
		ModelName:      "Pro",
		ProOnly:        true,
		Status:         1,
		ThinkingStatus: 1,
	}); err != nil {
		t.Fatal(err)
	}

	if got := checkModelAllowed(42, "deepseek-v4-pro", false); got != nil {
		t.Fatalf("restriction=%v, want nil", got)
	}
}

func TestCheckModelAllowedStillRejectsDisabledModelAndThinking(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})
	prices := []models.ModelPrice{
		{ModelID: "disabled", ModelName: "disabled", Status: 0, ThinkingStatus: 1},
		{ModelID: "normal-only", ModelName: "normal-only", Status: 1, ThinkingStatus: 0},
	}
	for _, price := range prices {
		if err := database.Get().Register("ModelPrice").Insert(&price); err != nil {
			t.Fatal(err)
		}
	}

	if got := checkModelAllowed(42, "disabled", false); got == nil {
		t.Fatal("disabled model was allowed")
	}
	if got := checkModelAllowed(42, "normal-only", true); got == nil {
		t.Fatal("unsupported thinking mode was allowed")
	}
}

func TestGetModelsHidesDisabledModels(t *testing.T) {
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})
	prices := []models.ModelPrice{
		{ModelID: "visible-m", ModelName: "Visible", Status: 1, ThinkingStatus: 1},
		{ModelID: "hidden-m", ModelName: "Hidden", Status: 0, ThinkingStatus: 1},
	}
	for _, p := range prices {
		if err := database.Get().Register("ModelPrice").Insert(&p); err != nil {
			t.Fatal(err)
		}
	}

	gin.SetMode(gin.TestMode)
	h := &ChatHandler{}
	router := gin.New()
	router.GET("/models", h.GetModels)

	getModelIDs := func() []string {
		req := httptest.NewRequest(http.MethodGet, "/models", nil)
		rec := httptest.NewRecorder()
		router.ServeHTTP(rec, req)
		var resp struct {
			Code int `json:"code"`
			Data struct {
				Models []struct {
					ID string `json:"id"`
				} `json:"models"`
			} `json:"data"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatalf("response not JSON: %v, body: %s", err, rec.Body.String())
		}
		if resp.Code != 0 {
			t.Fatalf("code = %d, want 0, body: %s", resp.Code, rec.Body.String())
		}
		ids := []string{}
		for _, m := range resp.Data.Models {
			ids = append(ids, m.ID)
		}
		return ids
	}

	// 隐藏模型不出现在客户端列表
	ids := getModelIDs()
	if len(ids) != 1 || ids[0] != "visible-m" {
		t.Fatalf("visible models = %v, want [visible-m]", ids)
	}

	// 全部隐藏后必须返回空列表，而不是回退到上游拉模型（那会绕过定价体系）
	database.Get().Register("ModelPrice").UpdateWhere(database.FilterEq("ModelID", "visible-m"), map[string]interface{}{"Status": 0})
	if ids := getModelIDs(); len(ids) != 0 {
		t.Fatalf("all-hidden models = %v, want empty", ids)
	}
}
