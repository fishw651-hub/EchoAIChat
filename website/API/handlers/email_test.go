package handlers

import "testing"

func TestIsSMTPConfigured(t *testing.T) {
	tests := []struct {
		name     string
		host     string
		username string
		from     string
		password string
		want     bool
	}{
		{
			name: "empty config is not configured",
			want: false,
		},
		{
			name: "host alone counts as configured",
			host: "smtp.example.com",
			want: true,
		},
		{
			name:     "legacy saved username and password still count as configured",
			username: "noreply@example.com",
			password: "encrypted-value",
			want:     true,
		},
		{
			name: "sender alone counts as configured for existing saved config",
			from: "noreply@example.com",
			want: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := isSMTPConfigured(tt.host, tt.username, tt.from, tt.password)
			if got != tt.want {
				t.Fatalf("isSMTPConfigured() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestParseNotifyUserIDs(t *testing.T) {
	ids, err := parseNotifyUserIDs([]string{"1", " 2 ", "3"})
	if err != nil {
		t.Fatalf("parseNotifyUserIDs returned error: %v", err)
	}
	if len(ids) != 3 || ids[0] != 1 || ids[1] != 2 || ids[2] != 3 {
		t.Fatalf("unexpected ids: %#v", ids)
	}

	if _, err := parseNotifyUserIDs([]string{"1", "bad"}); err == nil {
		t.Fatal("expected invalid id error")
	}

	numericIDs, err := parseNotifyUserIDs([]interface{}{float64(4), float64(5)})
	if err != nil {
		t.Fatalf("parseNotifyUserIDs numeric returned error: %v", err)
	}
	if len(numericIDs) != 2 || numericIDs[0] != 4 || numericIDs[1] != 5 {
		t.Fatalf("unexpected numeric ids: %#v", numericIDs)
	}
}
