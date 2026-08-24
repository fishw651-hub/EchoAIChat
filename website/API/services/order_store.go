package services

import (
	"aichat-api/database"
	"aichat-api/models"
)

// order_store.go — PaymentOrder 表数据访问薄封装，供 handlers 层使用。

// FindPaymentOrderByOrderNo 按订单号查支付订单；未找到返回 (nil, nil)。
func FindPaymentOrderByOrderNo(orderNo string) (*models.PaymentOrder, error) {
	var order models.PaymentOrder
	found, err := database.Get().Register("PaymentOrder").FindOneE(database.FilterEq("OrderNo", orderNo), &order)
	if err != nil || !found {
		return nil, err
	}
	return &order, nil
}

// ListPaymentOrders 列出全部支付订单（ID desc）。
func ListPaymentOrders() []models.PaymentOrder {
	var orders []models.PaymentOrder
	database.Get().Register("PaymentOrder").FindAll(&orders, nil, "ID desc", 0, 0)
	return orders
}

// CountPaymentOrdersByStatus 按状态统计订单数（COUNT 下推 SQL）。
func CountPaymentOrdersByStatus(status string) (int64, error) {
	return database.Get().Register("PaymentOrder").CountWhere(database.FilterEq("Status", status))
}
