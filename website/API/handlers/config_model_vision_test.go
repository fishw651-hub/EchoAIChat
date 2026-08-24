package handlers

import (
	"net/http"
	"testing"

	"aichat-api/database"
	"aichat-api/models"
	"aichat-api/utils"
)

// TestModelPriceVisionFieldsCreateAndList 验证创建端点保存视觉字段，列表端点原样返回。
func TestModelPriceVisionFieldsCreateAndList(t *testing.T) {
	router := setupConfigHandlerTest(t)

	// 非原生视觉 + 绑定视觉模型
	_, resp := doJSONRequest(t, router, http.MethodPost, "/model-prices",
		`{"model_id":"m-text","native_vision":false,"vision_model_id":"m-vision"}`)
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("create code = %d (%s), want success", resp.Code, resp.Message)
	}
	var saved models.ModelPrice
	if !database.Get().Register("ModelPrice").FindOne(database.FilterEq("ModelID", "m-text"), &saved) {
		t.Fatal("model price not persisted")
	}
	if saved.NativeVision {
		t.Fatal("native_vision should be false")
	}
	if saved.VisionModelID != "m-vision" {
		t.Fatalf("vision_model_id = %q, want m-vision", saved.VisionModelID)
	}

	// 原生视觉时忽略传入的绑定值
	_, resp = doJSONRequest(t, router, http.MethodPost, "/model-prices",
		`{"model_id":"m-vision","native_vision":true,"vision_model_id":"should-be-ignored"}`)
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("create native code = %d (%s), want success", resp.Code, resp.Message)
	}
	var savedNative models.ModelPrice
	if !database.Get().Register("ModelPrice").FindOne(database.FilterEq("ModelID", "m-vision"), &savedNative) {
		t.Fatal("native model price not persisted")
	}
	if !savedNative.NativeVision {
		t.Fatal("native_vision should be true")
	}
	if savedNative.VisionModelID != "" {
		t.Fatalf("vision_model_id = %q, want empty when native_vision is true", savedNative.VisionModelID)
	}

	// 默认（不传字段）应为 false / ""
	_, resp = doJSONRequest(t, router, http.MethodPost, "/model-prices", `{"model_id":"m-default"}`)
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("create default code = %d (%s), want success", resp.Code, resp.Message)
	}
	var savedDefault models.ModelPrice
	if !database.Get().Register("ModelPrice").FindOne(database.FilterEq("ModelID", "m-default"), &savedDefault) {
		t.Fatal("default model price not persisted")
	}
	if savedDefault.NativeVision || savedDefault.VisionModelID != "" {
		t.Fatalf("defaults mismatch: %+v", savedDefault)
	}

	// 列表端点返回两个字段
	_, resp = doJSONRequest(t, router, http.MethodGet, "/model-prices", "")
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("list code = %d, want success", resp.Code)
	}
	list, ok := resp.Data.([]interface{})
	if !ok || len(list) != 3 {
		t.Fatalf("list = %v, want 3 entries", resp.Data)
	}
	seen := map[string]map[string]interface{}{}
	for _, item := range list {
		entry := item.(map[string]interface{})
		seen[entry["model_id"].(string)] = entry
	}
	if seen["m-text"]["native_vision"] != false || seen["m-text"]["vision_model_id"] != "m-vision" {
		t.Fatalf("m-text entry mismatch: %v", seen["m-text"])
	}
	if seen["m-vision"]["native_vision"] != true || seen["m-vision"]["vision_model_id"] != "" {
		t.Fatalf("m-vision entry mismatch: %v", seen["m-vision"])
	}
	if seen["m-default"]["native_vision"] != false || seen["m-default"]["vision_model_id"] != "" {
		t.Fatalf("m-default entry mismatch: %v", seen["m-default"])
	}
}

// TestModelPriceVisionFieldsUpdate 验证更新端点接受并保存视觉字段，
// native_vision=true 时自动清空绑定，省略字段时保持原值。
func TestModelPriceVisionFieldsUpdate(t *testing.T) {
	router := setupConfigHandlerTest(t)

	price := models.ModelPrice{ModelID: "m-upd", Status: 1, NativeVision: false, VisionModelID: "v-old"}
	if err := database.Get().Register("ModelPrice").Insert(&price); err != nil {
		t.Fatalf("insert price: %v", err)
	}

	// 省略视觉字段 → 原值保留
	_, resp := doJSONRequest(t, router, http.MethodPut, "/model-prices/"+itoa(price.ID),
		`{"input_price_per_1m":1}`)
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("plain update code = %d (%s), want success", resp.Code, resp.Message)
	}
	var saved models.ModelPrice
	if !database.Get().Register("ModelPrice").FindByID(price.ID, &saved) {
		t.Fatal("model price lost after update")
	}
	if saved.VisionModelID != "v-old" {
		t.Fatalf("vision_model_id should stay, got %q", saved.VisionModelID)
	}

	// 改绑新视觉模型
	_, resp = doJSONRequest(t, router, http.MethodPut, "/model-prices/"+itoa(price.ID),
		`{"vision_model_id":"v-new"}`)
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("bind update code = %d (%s), want success", resp.Code, resp.Message)
	}
	if !database.Get().Register("ModelPrice").FindByID(price.ID, &saved) {
		t.Fatal("model price lost after bind update")
	}
	if saved.VisionModelID != "v-new" {
		t.Fatalf("vision_model_id = %q, want v-new", saved.VisionModelID)
	}

	// 勾选原生视觉 → 自动清空绑定
	_, resp = doJSONRequest(t, router, http.MethodPut, "/model-prices/"+itoa(price.ID),
		`{"native_vision":true}`)
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("native update code = %d (%s), want success", resp.Code, resp.Message)
	}
	if !database.Get().Register("ModelPrice").FindByID(price.ID, &saved) {
		t.Fatal("model price lost after native update")
	}
	if !saved.NativeVision || saved.VisionModelID != "" {
		t.Fatalf("native update mismatch: %+v", saved)
	}
}

// TestGetModelsReturnsVisionFields 验证 GetModels 输出 native_vision / vision_model_id。
func TestGetModelsReturnsVisionFields(t *testing.T) {
	router := setupConfigHandlerTest(t)
	chatHandler := &ChatHandler{}
	router.GET("/models", chatHandler.GetModels)

	prices := []models.ModelPrice{
		{ModelID: "m-vis", ModelName: "Vision", Status: 1, NativeVision: true},
		{ModelID: "m-bind", ModelName: "Text", Status: 1, VisionModelID: "m-vis"},
		{ModelID: "m-off", ModelName: "Off", Status: 0, NativeVision: true}, // 停用不出现在结果
	}
	for _, p := range prices {
		if err := database.Get().Register("ModelPrice").Insert(&p); err != nil {
			t.Fatalf("insert price: %v", err)
		}
	}

	_, resp := doJSONRequest(t, router, http.MethodGet, "/models", "")
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("get models code = %d, want success", resp.Code)
	}
	data, ok := resp.Data.(map[string]interface{})
	if !ok {
		t.Fatalf("unexpected data shape: %T", resp.Data)
	}
	modelsList, ok := data["models"].([]interface{})
	if !ok || len(modelsList) != 2 {
		t.Fatalf("models = %v, want 2 entries", data["models"])
	}
	seen := map[string]map[string]interface{}{}
	for _, item := range modelsList {
		entry := item.(map[string]interface{})
		seen[entry["id"].(string)] = entry
	}
	if seen["m-vis"]["native_vision"] != true {
		t.Fatalf("m-vis native_vision = %v, want true", seen["m-vis"]["native_vision"])
	}
	if seen["m-bind"]["native_vision"] != false || seen["m-bind"]["vision_model_id"] != "m-vis" {
		t.Fatalf("m-bind entry mismatch: %v", seen["m-bind"])
	}
	if _, ok := seen["m-off"]; ok {
		t.Fatal("disabled model should not be listed")
	}
}
