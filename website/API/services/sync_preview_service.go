package services

import (
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"slices"
	"sync"
	"time"
)

var (
	ErrSyncPreviewInvalid = errors.New("同步预览无效")
	ErrSyncPreviewExpired = errors.New("同步预览已过期")
	ErrSyncPreviewChanged = errors.New("同步预览条件已变化")
	ErrTooManyPreviews    = errors.New("待执行同步预览过多")
)

type SyncPreviewBinding struct {
	UserID        uint
	DeviceID      string
	Mode          string
	PolicyVersion uint64
	Scope         SyncScope
	PayloadHash   string
}

type syncPreviewEntry struct {
	binding   SyncPreviewBinding
	expiresAt time.Time
}

type SyncPreviewStore struct {
	mu      sync.Mutex
	ttl     time.Duration
	now     func() time.Time
	entries map[string]syncPreviewEntry
}

func NewSyncPreviewStore() *SyncPreviewStore {
	return newSyncPreviewStore(5*time.Minute, time.Now)
}

func newSyncPreviewStore(ttl time.Duration, now func() time.Time) *SyncPreviewStore {
	return &SyncPreviewStore{
		ttl: ttl, now: now, entries: make(map[string]syncPreviewEntry),
	}
}

var DefaultSyncPreviewStore = NewSyncPreviewStore()

func (s *SyncPreviewStore) Issue(binding SyncPreviewBinding) (string, time.Time, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := s.now().UTC()
	s.removeExpiredLocked(now)
	active := 0
	for _, entry := range s.entries {
		if entry.binding.UserID == binding.UserID && entry.binding.DeviceID == binding.DeviceID {
			active++
		}
	}
	if active >= 5 {
		return "", time.Time{}, ErrTooManyPreviews
	}

	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		return "", time.Time{}, fmt.Errorf("生成同步预览令牌: %w", err)
	}
	token := base64.RawURLEncoding.EncodeToString(bytes)
	expiresAt := now.Add(s.ttl)
	binding.Scope.AgentIDs = SortedScopeAgentIDs(binding.Scope)
	s.entries[token] = syncPreviewEntry{binding: binding, expiresAt: expiresAt}
	return token, expiresAt, nil
}

func (s *SyncPreviewStore) Consume(token string, actual SyncPreviewBinding) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	entry, ok := s.entries[token]
	if !ok {
		return ErrSyncPreviewInvalid
	}
	delete(s.entries, token)
	if !s.now().UTC().Before(entry.expiresAt) {
		return ErrSyncPreviewExpired
	}
	actual.Scope.AgentIDs = SortedScopeAgentIDs(actual.Scope)
	if !samePreviewBinding(entry.binding, actual) {
		return ErrSyncPreviewChanged
	}
	return nil
}

func (s *SyncPreviewStore) removeExpiredLocked(now time.Time) {
	for token, entry := range s.entries {
		if !now.Before(entry.expiresAt) {
			delete(s.entries, token)
		}
	}
}

func samePreviewBinding(expected, actual SyncPreviewBinding) bool {
	return expected.UserID == actual.UserID &&
		expected.DeviceID == actual.DeviceID &&
		expected.Mode == actual.Mode &&
		expected.PolicyVersion == actual.PolicyVersion &&
		expected.Scope.Mode == actual.Scope.Mode &&
		slices.Equal(expected.Scope.AgentIDs, actual.Scope.AgentIDs) &&
		expected.PayloadHash == actual.PayloadHash
}
