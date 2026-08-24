package services

import (
	"crypto/rand"
	"encoding/base64"
	"sync"
	"time"
)

type wsTicket struct {
	UserID    uint
	ExpiresAt time.Time
}

var wsTickets = struct {
	sync.Mutex
	values map[string]wsTicket
}{values: make(map[string]wsTicket)}

func IssueWSTicket(userID uint) (string, error) {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	ticket := base64.RawURLEncoding.EncodeToString(buf)
	wsTickets.Lock()
	wsTickets.values[ticket] = wsTicket{UserID: userID, ExpiresAt: time.Now().Add(time.Minute)}
	wsTickets.Unlock()
	return ticket, nil
}

func ConsumeWSTicket(ticket string) (uint, bool) {
	wsTickets.Lock()
	defer wsTickets.Unlock()
	entry, ok := wsTickets.values[ticket]
	delete(wsTickets.values, ticket)
	if !ok || time.Now().After(entry.ExpiresAt) {
		return 0, false
	}
	return entry.UserID, true
}
