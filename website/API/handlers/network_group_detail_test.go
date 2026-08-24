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

func TestNetworkGroupDetailIncludesDecryptedMembers(t *testing.T) {
	setupAiReviewTestDB(t)

	membersJSON, err := json.Marshal([]models.NetworkMemberPayload{
		{
			Name:              "小雨",
			Persona:           "温柔的图书管理员",
			OpeningLine:       "今天想读哪一本书？",
			Worldview:         "雨城图书馆",
			MaxResponseLength: 450,
			Role:              "moderator",
		},
	})
	if err != nil {
		t.Fatalf("marshal members: %v", err)
	}
	group := models.NetworkGroup{
		UploaderID:          1,
		Name:                "雨城书会",
		GroupPersona:        encryptField("在雨城图书馆举行的书会"),
		OpeningLine:         encryptField("窗外正在下雨。"),
		OpeningSpeakerIndex: 0,
		MembersJSON:         encryptField(string(membersJSON)),
		Status:              "approved",
		Version:             1,
	}
	if err := database.Get().Register("NetworkGroup").Insert(&group); err != nil {
		t.Fatalf("insert group: %v", err)
	}

	router := gin.New()
	router.GET("/groups/:id", (&NetworkGroupHandler{}).GetGroupDetail)
	recorder := doJSON(router, http.MethodGet, "/groups/1", "")

	var response struct {
		Code int `json:"code"`
		Data struct {
			Members []models.NetworkMemberPayload `json:"members"`
		} `json:"data"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if response.Code != utils.CodeSuccess {
		t.Fatalf("response code = %d, want %d; body=%s", response.Code, utils.CodeSuccess, recorder.Body.String())
	}
	if len(response.Data.Members) != 1 {
		t.Fatalf("members = %#v, want one member", response.Data.Members)
	}
	member := response.Data.Members[0]
	if member.Persona != "温柔的图书管理员" || member.OpeningLine != "今天想读哪一本书？" || member.Worldview != "雨城图书馆" || member.MaxResponseLength != 450 {
		t.Fatalf("member content was not preserved: %#v", member)
	}
}

func TestNetworkSimulatorGroupDetailAlwaysUsesNarratorOpening(t *testing.T) {
	setupAiReviewTestDB(t)

	group := models.NetworkGroup{
		UploaderID:          1,
		Name:                "旧模拟器群聊",
		OpeningLine:         encryptField("故事开始。"),
		OpeningSpeakerIndex: 0, // 历史记录缺少该字段时反序列化的零值。
		IsSimulatorMode:     true,
		Status:              "approved",
		Version:             1,
	}
	if err := database.Get().Register("NetworkGroup").Insert(&group); err != nil {
		t.Fatalf("insert group: %v", err)
	}

	router := gin.New()
	router.GET("/groups/:id", (&NetworkGroupHandler{}).GetGroupDetail)
	recorder := doJSON(router, http.MethodGet, "/groups/1", "")

	var response struct {
		Code int `json:"code"`
		Data struct {
			OpeningSpeakerIndex int `json:"opening_speaker_index"`
		} `json:"data"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if response.Code != utils.CodeSuccess {
		t.Fatalf("response code = %d, want %d; body=%s", response.Code, utils.CodeSuccess, recorder.Body.String())
	}
	if response.Data.OpeningSpeakerIndex != -1 {
		t.Fatalf("opening speaker index = %d, want -1 for simulator narrator", response.Data.OpeningSpeakerIndex)
	}
}

func TestPublicNetworkListsDisableCaching(t *testing.T) {
	setupAiReviewTestDB(t)

	router := gin.New()
	router.GET("/agents", (&NetworkAgentHandler{}).ListAgents)
	router.GET("/groups", (&NetworkGroupHandler{}).ListGroups)

	for _, testCase := range []struct {
		name string
		path string
	}{
		{name: "agents", path: "/agents"},
		{name: "groups", path: "/groups"},
	} {
		t.Run(testCase.name, func(t *testing.T) {
			recorder := doJSON(router, http.MethodGet, testCase.path, "")
			if got := recorder.Header().Get("Cache-Control"); got != "no-store" {
				t.Fatalf("Cache-Control = %q, want no-store", got)
			}
		})
	}
}
