package handlers

import (
	"encoding/json"
	"net/http"
	"testing"

	"aichat-api/database"
	"aichat-api/models"
	"aichat-api/utils"

	"github.com/gin-gonic/gin"
)

func responseCode(t *testing.T, recorderBody []byte) int {
	t.Helper()
	var resp utils.Response
	if err := json.Unmarshal(recorderBody, &resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	return resp.Code
}

func TestNetworkAgentUploadRejectsBlankOpeningLine(t *testing.T) {
	setupAiReviewTestDB(t)

	router := gin.New()
	router.POST("/agents", func(c *gin.Context) {
		c.Set("user_id", uint(1))
		(&NetworkAgentHandler{}).Upload(c)
	})

	recorder := doJSON(
		router,
		http.MethodPost,
		"/agents",
		`{"name":"A","persona":"P","opening_line":"  ","source_kind":"none"}`,
	)
	if got := responseCode(t, recorder.Body.Bytes()); got != utils.CodeBadRequest {
		t.Fatalf("blank opening line code = %d, want %d; body=%s", got, utils.CodeBadRequest, recorder.Body.String())
	}
}

func TestNetworkGroupUploadRejectsBlankOpeningLine(t *testing.T) {
	setupAiReviewTestDB(t)

	router := gin.New()
	router.POST("/groups", func(c *gin.Context) {
		c.Set("user_id", uint(1))
		(&NetworkGroupHandler{}).UploadGroup(c)
	})

	recorder := doJSON(
		router,
		http.MethodPost,
		"/groups",
		`{"name":"G","group_persona":"P","opening_line":"","source_kind":"none"}`,
	)
	if got := responseCode(t, recorder.Body.Bytes()); got != utils.CodeBadRequest {
		t.Fatalf("blank opening line code = %d, want %d; body=%s", got, utils.CodeBadRequest, recorder.Body.String())
	}
}

func TestNetworkUploadRejectsDownloadedSource(t *testing.T) {
	tests := []struct {
		name string
		path string
		body string
		bind func(*gin.Engine)
	}{
		{
			name: "agent",
			path: "/agents",
			body: `{"name":"A","persona":"P","opening_line":"Hi","source_kind":"downloaded"}`,
			bind: func(router *gin.Engine) {
				router.POST("/agents", func(c *gin.Context) {
					c.Set("user_id", uint(1))
					(&NetworkAgentHandler{}).Upload(c)
				})
			},
		},
		{
			name: "group",
			path: "/groups",
			body: `{"name":"G","group_persona":"P","opening_line":"Hi","source_kind":"downloaded"}`,
			bind: func(router *gin.Engine) {
				router.POST("/groups", func(c *gin.Context) {
					c.Set("user_id", uint(1))
					(&NetworkGroupHandler{}).UploadGroup(c)
				})
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			setupAiReviewTestDB(t)
			router := gin.New()
			tt.bind(router)

			recorder := doJSON(router, http.MethodPost, tt.path, tt.body)
			if got := responseCode(t, recorder.Body.Bytes()); got != utils.CodeForbidden {
				t.Fatalf("downloaded source code = %d, want %d; body=%s", got, utils.CodeForbidden, recorder.Body.String())
			}
		})
	}
}

func TestNetworkAgentEditRejectsBlankOpeningLine(t *testing.T) {
	setupAiReviewTestDB(t)

	agent := models.NetworkAgent{
		UploaderID:  1,
		Name:        "A",
		Persona:     "P",
		OpeningLine: "Hi",
		Status:      "approved",
		Version:     1,
	}
	if err := database.Get().Register("NetworkAgent").Insert(&agent); err != nil {
		t.Fatalf("insert agent: %v", err)
	}

	router := gin.New()
	router.PUT("/agents/:id", func(c *gin.Context) {
		c.Set("user_id", uint(1))
		(&NetworkAgentHandler{}).Edit(c)
	})
	recorder := doJSON(router, http.MethodPut, "/agents/1", `{"opening_line":"  "}`)
	if got := responseCode(t, recorder.Body.Bytes()); got != utils.CodeBadRequest {
		t.Fatalf("blank opening line code = %d, want %d; body=%s", got, utils.CodeBadRequest, recorder.Body.String())
	}
}

func TestNetworkGroupEditRejectsBlankOpeningLine(t *testing.T) {
	setupAiReviewTestDB(t)

	group := models.NetworkGroup{
		UploaderID: 1,
		Name:       "G",
		Status:     "approved",
		Version:    1,
	}
	if err := database.Get().Register("NetworkGroup").Insert(&group); err != nil {
		t.Fatalf("insert group: %v", err)
	}

	router := gin.New()
	router.PUT("/groups/:id", func(c *gin.Context) {
		c.Set("user_id", uint(1))
		(&NetworkGroupHandler{}).EditGroup(c)
	})
	recorder := doJSON(router, http.MethodPut, "/groups/1", `{"opening_line":""}`)
	if got := responseCode(t, recorder.Body.Bytes()); got != utils.CodeBadRequest {
		t.Fatalf("blank opening line code = %d, want %d; body=%s", got, utils.CodeBadRequest, recorder.Body.String())
	}
}
