package dto

// Response 統一 API 回應格式
type Response struct {
	Code    int         `json:"code"`           // HTTP 狀態碼
	Message string      `json:"message"`        // 訊息
	Data    interface{} `json:"data,omitempty"` // 資料
}

// SuccessResponse 成功回應
func SuccessResponse(data interface{}, message ...string) Response {
	msg := "Success"
	if len(message) > 0 {
		msg = message[0]
	}
	return Response{
		Code:    200,
		Message: msg,
		Data:    data,
	}
}

// ErrorResponse 錯誤回應
func ErrorResponse(code int, message string) Response {
	return Response{
		Code:    code,
		Message: message,
		Data:    nil,
	}
}

// CreatedResponse 創建成功回應 (201)
func CreatedResponse(data interface{}, message ...string) Response {
	msg := "Created successfully"
	if len(message) > 0 {
		msg = message[0]
	}
	return Response{
		Code:    201,
		Message: msg,
		Data:    data,
	}
}

// BadRequestResponse 錯誤請求 (400)
func BadRequestResponse(message string) Response {
	return Response{
		Code:    400,
		Message: message,
		Data:    nil,
	}
}

// UnauthorizedResponse 未授權 (401)
func UnauthorizedResponse(message string) Response {
	return Response{
		Code:    401,
		Message: message,
		Data:    nil,
	}
}

// ForbiddenResponse 禁止訪問 (403)
func ForbiddenResponse(message string) Response {
	return Response{
		Code:    403,
		Message: message,
		Data:    nil,
	}
}

// NotFoundResponse 未找到 (404)
func NotFoundResponse(message string) Response {
	return Response{
		Code:    404,
		Message: message,
		Data:    nil,
	}
}

// InternalServerErrorResponse 伺服器錯誤 (500)
func InternalServerErrorResponse(message string) Response {
	return Response{
		Code:    500,
		Message: message,
		Data:    nil,
	}
}
