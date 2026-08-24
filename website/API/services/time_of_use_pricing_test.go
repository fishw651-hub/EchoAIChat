package services

import (
	"testing"
	"time"
)

func TestTimeOfUsePricingUsesShanghaiHalfOpenValleyWindow(t *testing.T) {
	location, err := time.LoadLocation("Asia/Shanghai")
	if err != nil {
		t.Fatal(err)
	}
	pricing := TimeOfUsePricing{
		ValleyStart:      "00:00",
		ValleyEnd:        "08:00",
		PeakMultiplier:   1.2,
		ValleyMultiplier: 0.8,
	}

	for _, testCase := range []struct {
		name   string
		at     time.Time
		period string
		factor float64
	}{
		{"谷开始", time.Date(2026, 7, 13, 0, 0, 0, 0, location), "valley", 0.8},
		{"谷结束前", time.Date(2026, 7, 13, 7, 59, 0, 0, location), "valley", 0.8},
		{"峰开始", time.Date(2026, 7, 13, 8, 0, 0, 0, location), "peak", 1.2},
	} {
		t.Run(testCase.name, func(t *testing.T) {
			period, factor, err := pricing.MultiplierAt(testCase.at)
			if err != nil {
				t.Fatal(err)
			}
			if period != testCase.period || factor != testCase.factor {
				t.Fatalf("period=%q factor=%v, want %q/%v", period, factor, testCase.period, testCase.factor)
			}
		})
	}
}

func TestTimeOfUsePricingSupportsCrossMidnightAndRejectsInvalidValues(t *testing.T) {
	location, err := time.LoadLocation("Asia/Shanghai")
	if err != nil {
		t.Fatal(err)
	}
	pricing := TimeOfUsePricing{
		ValleyStart: "22:00", ValleyEnd: "06:00",
		PeakMultiplier: 1, ValleyMultiplier: 0.6,
	}
	period, factor, err := pricing.MultiplierAt(time.Date(2026, 7, 13, 1, 0, 0, 0, location))
	if err != nil || period != "valley" || factor != 0.6 {
		t.Fatalf("cross-midnight period=%q factor=%v err=%v", period, factor, err)
	}

	invalid := TimeOfUsePricing{
		ValleyStart: "08:00", ValleyEnd: "08:00",
		PeakMultiplier: 1, ValleyMultiplier: 0,
	}
	if err := invalid.Validate(); err == nil {
		t.Fatal("Validate() accepted identical window and zero multiplier")
	}
}
