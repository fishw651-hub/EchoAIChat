package utils

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

type Response struct {
	Code    int         `json:"code"`
	Message string      `json:"message"`
	Data    interface{} `json:"data"`
}

const (
	CodeSuccess      = 0
	CodeBadRequest   = 40000
	CodeUnauthorized = 40100
	CodeForbidden    = 40300
	CodeNotFound     = 40400
	CodeConflict     = 40900
	CodeTooManyReqs  = 42900
	CodeInternal     = 50000
	CodeBadGateway   = 50200
)

const (
	MistakeModelNotAllowed     = "model_not_allowed"
	MistakeThinkingNotAllowed  = "thinking_not_allowed"
	MistakeBalanceInsufficient = "balance_insufficient"
)

func Success(c *gin.Context, data interface{}) {
	c.JSON(http.StatusOK, Response{Code: CodeSuccess, Message: "success", Data: data})
}

func SuccessMsg(c *gin.Context, msg string) {
	c.JSON(http.StatusOK, Response{Code: CodeSuccess, Message: msg, Data: nil})
}

func Fail(c *gin.Context, code int, msg string) {
	c.JSON(http.StatusOK, Response{Code: code, Message: msg, Data: nil})
}

func BadRequest(c *gin.Context, msg string) {
	c.JSON(http.StatusOK, Response{Code: CodeBadRequest, Message: msg, Data: nil})
}

func Unauthorized(c *gin.Context, msg string) {
	c.JSON(http.StatusUnauthorized, Response{Code: CodeUnauthorized, Message: msg, Data: nil})
}

func Forbidden(c *gin.Context, msg string) {
	c.JSON(http.StatusForbidden, Response{Code: CodeForbidden, Message: msg, Data: nil})
}

func NotFound(c *gin.Context, msg string) {
	c.JSON(http.StatusOK, Response{Code: CodeNotFound, Message: msg, Data: nil})
}

func Internal(c *gin.Context, msg string) {
	c.JSON(http.StatusOK, Response{Code: CodeInternal, Message: msg, Data: nil})
}

func FailWithData(c *gin.Context, code int, msg string, data interface{}) {
	c.JSON(http.StatusOK, Response{Code: code, Message: msg, Data: data})
}
