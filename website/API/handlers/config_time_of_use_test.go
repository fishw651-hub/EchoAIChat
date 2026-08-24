package handlers

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"aichat-api/database"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

func TestConfigHandlerUpdatesTimeOfUsePricing(t *testing.T) {
	gin.SetMode(gin.TestMode)
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})

	router := gin.New()
	handler := &ConfigHandler{}
	router.PUT("/pricing", handler.UpdateTimeOfUsePricing)

	req := httptest.NewRequest(http.MethodPut, "/pricing", bytes.NewBufferString(`{
      "valley_start":"22:00",
      "valley_end":"06:00",
      "peak_multiplier":1.2,
      "valley_multiplier":0.8
    }`))
	req.Header.Set("Content-Type", "application/json")
	recorder := httptest.NewRecorder()
	router.ServeHTTP(recorder, req)

	var response utils.Response
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	if response.Code != utils.CodeSuccess {
		t.Fatalf("response=%d body=%s", response.Code, recorder.Body.String())
	}
	pricing, err := services.LoadTimeOfUsePricing()
	if err != nil || pricing.ValleyStart != "22:00" || pricing.ValleyMultiplier != 0.8 {
		t.Fatalf("pricing=%+v err=%v", pricing, err)
	}
}

func TestConfigHandlerRejectsInvalidTimeOfUsePricing(t *testing.T) {
	gin.SetMode(gin.TestMode)
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})

	router := gin.New()
	router.PUT("/pricing", (&ConfigHandler{}).UpdateTimeOfUsePricing)
	req := httptest.NewRequest(http.MethodPut, "/pricing", bytes.NewBufferString(`{
      "valley_start":"08:00",
      "valley_end":"08:00",
      "peak_multiplier":1,
      "valley_multiplier":0
    }`))
	req.Header.Set("Content-Type", "application/json")
	recorder := httptest.NewRecorder()
	router.ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", recorder.Code, recorder.Body.String())
	}
	var response utils.Response
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatal(err)
	}
	if response.Code != utils.CodeBadRequest {
		t.Fatalf("response=%d body=%s", response.Code, recorder.Body.String())
	}
}
