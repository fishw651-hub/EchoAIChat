package handlers

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"

	"aichat-api/config"
	"aichat-api/database"
	"aichat-api/models"
	"aichat-api/services"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

func setupConfigHandlerTest(t *testing.T) *gin.Engine {
	t.Helper()
	gin.SetMode(gin.TestMode)
	if err := database.Init(t.TempDir()); err != nil {
		t.Fatalf("database init: %v", err)
	}
	t.Cleanup(func() {
		if db := database.Get(); db != nil {
			_ = db.Close()
		}
	})
	oldCfg := config.AppConfig
	config.AppConfig = &config.Config{}
	config.AppConfig.Encryption.Key = "config-handler-test-key"
	t.Cleanup(func() { config.AppConfig = oldCfg })

	h := &ConfigHandler{}
	router := gin.New()
	router.POST("/model-prices", h.CreateModelPrice)
	router.PUT("/model-prices/:id", h.UpdateModelPrice)
	router.PUT("/model-prices/:id/status", h.UpdateModelPriceStatus)
	router.GET("/model-prices", h.ListModelPrices)
	router.DELETE("/model-prices/:id", h.DeleteModelPrice)
	router.POST("/models/fetch-remote", h.FetchRemoteModels)
	router.POST("/api-keys", h.CreateAPIKey)
	router.PUT("/api-keys/:id", h.UpdateAPIKey)
	return router
}

func doJSONRequest(t *testing.T, router *gin.Engine, method, path, body string) (int, utils.Response) {
	t.Helper()
	req := httptest.NewRequest(method, path, bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	var resp utils.Response
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("response not JSON: %v, body: %s", err, rec.Body.String())
	}
	return rec.Code, resp
}

func TestCreateModelPriceValidation(t *testing.T) {
	router := setupConfigHandlerTest(t)

	// 缺 model_id → 拒绝
	_, resp := doJSONRequest(t, router, http.MethodPost, "/model-prices", `{"model_name":"x"}`)
	if resp.Code != utils.CodeBadRequest {
		t.Fatalf("missing model_id code = %d, want %d", resp.Code, utils.CodeBadRequest)
	}

	// 负数价格 → 拒绝
	_, resp = doJSONRequest(t, router, http.MethodPost, "/model-prices", `{"model_id":"m-neg","input_price_per_1m":-1}`)
	if resp.Code != utils.CodeBadRequest {
		t.Fatalf("negative price code = %d, want %d", resp.Code, utils.CodeBadRequest)
	}

	// 正常创建
	_, resp = doJSONRequest(t, router, http.MethodPost, "/model-prices",
		`{"model_id":"gemini-2.5-flash","model_name":"Gemini","provider":"gemini","input_price_per_1m":1.5,"output_price_per_1m":3,"status":1,"thinking_status":0}`)
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("create code = %d (%s), want success", resp.Code, resp.Message)
	}
	var saved models.ModelPrice
	if !database.Get().Register("ModelPrice").FindOne(database.FilterEq("ModelID", "gemini-2.5-flash"), &saved) {
		t.Fatal("model price not persisted")
	}
	if saved.Provider != "gemini" || saved.InputPricePer1M != 1.5 || saved.OutputPricePer1M != 3 {
		t.Fatalf("saved record mismatch: %+v", saved)
	}

	// 重复 model_id → 拒绝
	_, resp = doJSONRequest(t, router, http.MethodPost, "/model-prices", `{"model_id":"gemini-2.5-flash"}`)
	if resp.Code != utils.CodeConflict {
		t.Fatalf("duplicate code = %d, want %d", resp.Code, utils.CodeConflict)
	}
}

func TestDeleteModelPrice(t *testing.T) {
	router := setupConfigHandlerTest(t)


	price := models.ModelPrice{ModelID: "m-del", Status: 1}
	if err := database.Get().Register("ModelPrice").Insert(&price); err != nil {
		t.Fatalf("insert price: %v", err)
	}

	_, resp := doJSONRequest(t, router, http.MethodDelete, "/model-prices/"+itoa(price.ID), "")
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("delete code = %d, want success", resp.Code)
	}
	var gone models.ModelPrice
	if database.Get().Register("ModelPrice").FindByID(price.ID, &gone) {
		t.Fatal("model price should be deleted")
	}

	_, resp = doJSONRequest(t, router, http.MethodDelete, "/model-prices/"+itoa(price.ID), "")
	if resp.Code != utils.CodeNotFound {
		t.Fatalf("delete missing code = %d, want %d", resp.Code, utils.CodeNotFound)
	}
}

func TestUpdateModelPriceStatus(t *testing.T) {
	router := setupConfigHandlerTest(t)

	price := models.ModelPrice{
		ModelID: "m-toggle", ModelName: "Toggle", Provider: "deepseek",
		InputPricePer1M: 2, InputCacheHitPricePer1M: 1, OutputPricePer1M: 6,
		ThinkingInputPricePer1M: 4, ThinkingInputCacheHitPricePer1M: 2, ThinkingOutputPricePer1M: 12,
		Status: 1, ThinkingStatus: 1,
	}
	if err := database.Get().Register("ModelPrice").Insert(&price); err != nil {
		t.Fatalf("insert price: %v", err)
	}
	statusPath := "/model-prices/" + itoa(price.ID) + "/status"
	reload := func() models.ModelPrice {
		var cur models.ModelPrice
		if !database.Get().Register("ModelPrice").FindByID(price.ID, &cur) {
			t.Fatal("model price missing")
		}
		return cur
	}

	// 隐藏：状态切 0，价格等字段必须原样保留
	_, resp := doJSONRequest(t, router, http.MethodPut, statusPath, `{"status":0}`)
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("hide code = %d (%s), want success", resp.Code, resp.Message)
	}
	cur := reload()
	if cur.Status != 0 {
		t.Fatalf("status = %d, want 0", cur.Status)
	}
	if cur.InputPricePer1M != 2 || cur.InputCacheHitPricePer1M != 1 || cur.OutputPricePer1M != 6 ||
		cur.ThinkingInputPricePer1M != 4 || cur.ThinkingInputCacheHitPricePer1M != 2 || cur.ThinkingOutputPricePer1M != 12 ||
		cur.ThinkingStatus != 1 || cur.Provider != "deepseek" {
		t.Fatalf("fields clobbered: %+v", cur)
	}

	// 恢复上线
	_, resp = doJSONRequest(t, router, http.MethodPut, statusPath, `{"status":1}`)
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("restore code = %d (%s), want success", resp.Code, resp.Message)
	}
	if cur := reload(); cur.Status != 1 {
		t.Fatalf("status = %d, want 1", cur.Status)
	}

	// 非法状态值 → 400
	_, resp = doJSONRequest(t, router, http.MethodPut, statusPath, `{"status":5}`)
	if resp.Code != utils.CodeBadRequest {
		t.Fatalf("invalid status code = %d, want %d", resp.Code, utils.CodeBadRequest)
	}

	// 缺 status 字段 → 400（防止空请求误清状态）
	_, resp = doJSONRequest(t, router, http.MethodPut, statusPath, `{}`)
	if resp.Code != utils.CodeBadRequest {
		t.Fatalf("missing status code = %d, want %d", resp.Code, utils.CodeBadRequest)
	}

	// 不存在的记录 → 404
	_, resp = doJSONRequest(t, router, http.MethodPut, "/model-prices/99999/status", `{"status":0}`)
	if resp.Code != utils.CodeNotFound {
		t.Fatalf("missing record code = %d, want %d", resp.Code, utils.CodeNotFound)
	}
}

func TestAPIKeyFormatWhitelist(t *testing.T) {
	router := setupConfigHandlerTest(t)

	// 非法 api_format → 拒绝
	_, resp := doJSONRequest(t, router, http.MethodPost, "/api-keys",
		`{"provider":"gemini","name":"k1","api_key":"sk-1","api_format":"anthropic"}`)
	if resp.Code != utils.CodeBadRequest {
		t.Fatalf("invalid format code = %d, want %d", resp.Code, utils.CodeBadRequest)
	}

	// gemini 格式 + base_url 正常保存
	_, resp = doJSONRequest(t, router, http.MethodPost, "/api-keys",
		`{"provider":"gemini","name":"k1","api_key":"sk-1","base_url":"https://g.example.com","api_format":"gemini"}`)
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("create code = %d (%s), want success", resp.Code, resp.Message)
	}
	var key models.APIKey
	if !database.Get().Register("APIKey").FindOne(database.FilterEq("Name", "k1"), &key) {
		t.Fatal("api key not persisted")
	}
	if key.ApiFormat != "gemini" || key.BaseURL != "https://g.example.com" {
		t.Fatalf("saved key mismatch: %+v", key)
	}

	// 空 api_format 默认 openai
	_, resp = doJSONRequest(t, router, http.MethodPost, "/api-keys",
		`{"provider":"deepseek","name":"k2","api_key":"sk-2"}`)
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("create code = %d (%s), want success", resp.Code, resp.Message)
	}
	var key2 models.APIKey
	if !database.Get().Register("APIKey").FindOne(database.FilterEq("Name", "k2"), &key2) {
		t.Fatal("api key k2 not persisted")
	}
	if key2.ApiFormat != "openai" {
		t.Fatalf("default api_format = %q, want openai", key2.ApiFormat)
	}

	// Update 时非法 api_format → 拒绝，合法 → 更新
	_, resp = doJSONRequest(t, router, http.MethodPut, "/api-keys/"+itoa(key.ID), `{"api_format":"claude"}`)
	if resp.Code != utils.CodeBadRequest {
		t.Fatalf("update invalid format code = %d, want %d", resp.Code, utils.CodeBadRequest)
	}
	_, resp = doJSONRequest(t, router, http.MethodPut, "/api-keys/"+itoa(key.ID), `{"api_format":"openai","base_url":"https://o.example.com"}`)
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("update code = %d (%s), want success", resp.Code, resp.Message)
	}
	var updated models.APIKey
	if !database.Get().Register("APIKey").FindByID(key.ID, &updated) {
		t.Fatal("api key lost after update")
	}
	if updated.ApiFormat != "openai" || updated.BaseURL != "https://o.example.com" {
		t.Fatalf("updated key mismatch: %+v", updated)
	}
}

func itoa(v uint) string {
	return strconv.FormatUint(uint64(v), 10)
}

func TestFetchRemoteModels(t *testing.T) {
	router := setupConfigHandlerTest(t)

	// 模拟上游 /models：成功返回 OpenAI 格式模型列表
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/models" {
			http.Error(w, "not found", http.StatusNotFound)
			return
		}
		if r.Header.Get("Authorization") != "Bearer sk-test" {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"object":"list","data":[{"id":"gemini-2.5-flash"},{"id":"gemini-2.5-pro"},{"id":""}]}`)
	}))
	defer upstream.Close()

	_, resp := doJSONRequest(t, router, http.MethodPost, "/models/fetch-remote",
		`{"base_url":"`+upstream.URL+`/v1/","api_key":"sk-test","api_format":"openai"}`)
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("fetch code = %d (%s), want success", resp.Code, resp.Message)
	}
	data, ok := resp.Data.(map[string]interface{})
	if !ok {
		t.Fatalf("unexpected data shape: %T", resp.Data)
	}
	models, ok := data["models"].([]interface{})
	if !ok || len(models) != 2 {
		t.Fatalf("models = %v, want 2 ids", data["models"])
	}

	// 上游失败（鉴权不通过）→ 502 类错误
	_, resp = doJSONRequest(t, router, http.MethodPost, "/models/fetch-remote",
		`{"base_url":"`+upstream.URL+`/v1","api_key":"wrong"}`)
	if resp.Code != utils.CodeBadGateway {
		t.Fatalf("upstream failure code = %d, want %d", resp.Code, utils.CodeBadGateway)
	}

	// 空地址 / 非法地址 → 40000
	_, resp = doJSONRequest(t, router, http.MethodPost, "/models/fetch-remote", `{"base_url":""}`)
	if resp.Code != utils.CodeBadRequest {
		t.Fatalf("empty url code = %d, want %d", resp.Code, utils.CodeBadRequest)
	}
	_, resp = doJSONRequest(t, router, http.MethodPost, "/models/fetch-remote", `{"base_url":"not-a-url"}`)
	if resp.Code != utils.CodeBadRequest {
		t.Fatalf("invalid url code = %d, want %d", resp.Code, utils.CodeBadRequest)
	}

	// SSRF 拦截：非 http/https scheme → 40000
	_, resp = doJSONRequest(t, router, http.MethodPost, "/models/fetch-remote", `{"base_url":"ftp://evil.example.com"}`)
	if resp.Code != utils.CodeBadRequest {
		t.Fatalf("ssrf scheme code = %d, want %d", resp.Code, utils.CodeBadRequest)
	}
	_, resp = doJSONRequest(t, router, http.MethodPost, "/models/fetch-remote", `{"base_url":"file:///etc/passwd"}`)
	if resp.Code != utils.CodeBadRequest {
		t.Fatalf("ssrf file code = %d, want %d", resp.Code, utils.CodeBadRequest)
	}
}

func TestCreateModelPriceSiteUpsert(t *testing.T) {
	router := setupConfigHandlerTest(t)
	encKey := services.NormalizeEncryptionKey(config.AppConfig.Encryption.Key)

	// 无 key 的新站点 → 拒绝
	_, resp := doJSONRequest(t, router, http.MethodPost, "/model-prices",
		`{"model_id":"m-nokey","provider":"newsite","base_url":"https://n.example.com"}`)
	if resp.Code != utils.CodeBadRequest {
		t.Fatalf("new site without key code = %d (%s), want %d", resp.Code, resp.Message, utils.CodeBadRequest)
	}

	// 新站点 + key → 创建 APIKey 记录
	_, resp = doJSONRequest(t, router, http.MethodPost, "/model-prices",
		`{"model_id":"m-a","provider":"newsite","base_url":"https://n.example.com","api_format":"gemini","api_key":"sk-new","input_price_per_1m":1}`)
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("create code = %d (%s), want success", resp.Code, resp.Message)
	}
	var key models.APIKey
	if !database.Get().Register("APIKey").FindOne(database.FilterEq("Provider", "newsite"), &key) {
		t.Fatal("provider api key not created")
	}
	if key.BaseURL != "https://n.example.com" || key.ApiFormat != "gemini" || !key.IsActive {
		t.Fatalf("created key mismatch: %+v", key)
	}
	if plain, err := services.Decrypt(key.APIKeyEncrypted, encKey); err != nil || plain != "sk-new" {
		t.Fatalf("decrypt = %q, %v; want sk-new", plain, err)
	}

	// 同站点第二个模型：更新 base_url，key 留空保留原 key
	oldEncrypted := key.APIKeyEncrypted
	_, resp = doJSONRequest(t, router, http.MethodPost, "/model-prices",
		`{"model_id":"m-b","provider":"newsite","base_url":"https://n2.example.com","api_key":""}`)
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("second create code = %d (%s), want success", resp.Code, resp.Message)
	}
	var keys []models.APIKey
	database.Get().Register("APIKey").FindAll(&keys, nil, "", 0, 0)
	count := 0
	var updated models.APIKey
	for _, k := range keys {
		if k.Provider == "newsite" {
			count++
			updated = k
		}
	}
	if count != 1 {
		t.Fatalf("expected 1 key for newsite, got %d", count)
	}
	if updated.BaseURL != "https://n2.example.com" {
		t.Fatalf("base_url not updated: %q", updated.BaseURL)
	}
	if updated.APIKeyEncrypted != oldEncrypted {
		t.Fatal("api key should be kept when api_key is empty")
	}
	if updated.ApiFormat != "gemini" {
		t.Fatalf("api_format should be kept when omitted, got %q", updated.ApiFormat)
	}
}

func TestUpdateModelPriceSiteSync(t *testing.T) {
	router := setupConfigHandlerTest(t)
	encKey := services.NormalizeEncryptionKey(config.AppConfig.Encryption.Key)

	encrypted, err := services.Encrypt("sk-old", encKey)
	if err != nil {
		t.Fatalf("encrypt: %v", err)
	}
	siteKey := models.APIKey{Provider: "site-x", Name: "site-x", APIKeyEncrypted: encrypted, BaseURL: "https://x.example.com", ApiFormat: "openai", IsActive: true}
	if err := database.Get().Register("APIKey").Insert(&siteKey); err != nil {
		t.Fatalf("insert key: %v", err)
	}
	price := models.ModelPrice{ModelID: "m-x", Provider: "site-x", Status: 1}
	if err := database.Get().Register("ModelPrice").Insert(&price); err != nil {
		t.Fatalf("insert price: %v", err)
	}

	// 带站点字段：base_url/api_key 同步更新
	_, resp := doJSONRequest(t, router, http.MethodPut, "/model-prices/"+itoa(price.ID),
		`{"input_price_per_1m":2,"base_url":"https://x2.example.com","api_key":"sk-new"}`)
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("update code = %d (%s), want success", resp.Code, resp.Message)
	}
	var key models.APIKey
	if !database.Get().Register("APIKey").FindByID(siteKey.ID, &key) {
		t.Fatal("api key lost after update")
	}
	if key.BaseURL != "https://x2.example.com" {
		t.Fatalf("base_url not synced: %q", key.BaseURL)
	}
	if plain, err := services.Decrypt(key.APIKeyEncrypted, encKey); err != nil || plain != "sk-new" {
		t.Fatalf("decrypt = %q, %v; want sk-new", plain, err)
	}

	// 不带站点字段：站点配置保持不变（向后兼容）
	_, resp = doJSONRequest(t, router, http.MethodPut, "/model-prices/"+itoa(price.ID), `{"input_price_per_1m":3}`)
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("plain update code = %d (%s), want success", resp.Code, resp.Message)
	}
	if !database.Get().Register("APIKey").FindByID(siteKey.ID, &key) {
		t.Fatal("api key lost after plain update")
	}
	if key.BaseURL != "https://x2.example.com" {
		t.Fatalf("base_url should stay unchanged, got %q", key.BaseURL)
	}

	// 模型无站点记录时带 key → 自动创建
	price2 := models.ModelPrice{ModelID: "m-y", Provider: "site-y", Status: 1}
	if err := database.Get().Register("ModelPrice").Insert(&price2); err != nil {
		t.Fatalf("insert price2: %v", err)
	}
	_, resp = doJSONRequest(t, router, http.MethodPut, "/model-prices/"+itoa(price2.ID),
		`{"input_price_per_1m":1,"base_url":"https://y.example.com","api_key":"sk-y"}`)
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("create-on-update code = %d (%s), want success", resp.Code, resp.Message)
	}
	var key2 models.APIKey
	if !database.Get().Register("APIKey").FindOne(database.FilterEq("Provider", "site-y"), &key2) {
		t.Fatal("api key not auto-created on update")
	}
}

func TestListModelPricesSiteInfo(t *testing.T) {
	router := setupConfigHandlerTest(t)

	encrypted, err := services.Encrypt("sk-site", services.NormalizeEncryptionKey(config.AppConfig.Encryption.Key))
	if err != nil {
		t.Fatalf("encrypt: %v", err)
	}
	if err := database.Get().Register("APIKey").Insert(&models.APIKey{
		Provider: "gemini", Name: "gemini", APIKeyEncrypted: encrypted,
		BaseURL: "https://g.example.com", ApiFormat: "gemini", IsActive: true,
	}); err != nil {
		t.Fatalf("insert key: %v", err)
	}
	if err := database.Get().Register("ModelPrice").Insert(&models.ModelPrice{ModelID: "m-list", Provider: "gemini", Status: 1}); err != nil {
		t.Fatalf("insert price: %v", err)
	}
	if err := database.Get().Register("ModelPrice").Insert(&models.ModelPrice{ModelID: "m-nosite", Provider: "nosite", Status: 1}); err != nil {
		t.Fatalf("insert price2: %v", err)
	}

	_, resp := doJSONRequest(t, router, http.MethodGet, "/model-prices", "")
	if resp.Code != utils.CodeSuccess {
		t.Fatalf("list code = %d, want success", resp.Code)
	}
	list, ok := resp.Data.([]interface{})
	if !ok || len(list) != 2 {
		t.Fatalf("list = %v, want 2 entries", resp.Data)
	}
	var withSite, noSite map[string]interface{}
	for _, item := range list {
		entry := item.(map[string]interface{})
		if entry["model_id"] == "m-list" {
			withSite = entry
		} else {
			noSite = entry
		}
	}
	if withSite["base_url"] != "https://g.example.com" || withSite["api_format"] != "gemini" || withSite["has_key"] != true {
		t.Fatalf("site info mismatch: %v", withSite)
	}
	if _, leaked := withSite["api_key"]; leaked {
		t.Fatal("api key must not be returned")
	}
	if noSite["has_key"] != false || noSite["base_url"] != "" {
		t.Fatalf("no-site entry mismatch: %v", noSite)
	}
}
