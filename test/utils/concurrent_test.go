package utils

import (
	"context"
	"errors"
	"strconv"
	"sync/atomic"
	"testing"
	"time"
)

func TestSubmitConcurrently(t *testing.T) {
	const (
		concurrency = 5
		total       = 100
	)

	var active atomic.Int32
	var maximum atomic.Int32
	var completed atomic.Int32

	err := SubmitConcurrently(t.Context(), concurrency, func(yield func(string) error) error {
		for i := range total {
			if err := yield(strconv.Itoa(i)); err != nil {
				return err
			}
		}
		return nil
	}, func(context.Context, string) error {
		current := active.Add(1)
		defer active.Add(-1)
		for {
			observed := maximum.Load()
			if current <= observed || maximum.CompareAndSwap(observed, current) {
				break
			}
		}
		time.Sleep(time.Millisecond)
		completed.Add(1)
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if completed.Load() != total {
		t.Fatalf("completed %d submissions, want %d", completed.Load(), total)
	}
	if maximum.Load() < 2 || maximum.Load() > concurrency {
		t.Fatalf("maximum concurrency was %d, want 2..%d", maximum.Load(), concurrency)
	}
}

func TestSubmitConcurrentlyReturnsWorkerError(t *testing.T) {
	want := errors.New("submission failed")
	err := SubmitConcurrently(t.Context(), 5, func(yield func(string) error) error {
		for i := range 100 {
			if err := yield(strconv.Itoa(i)); err != nil {
				return err
			}
		}
		return nil
	}, func(_ context.Context, job string) error {
		if job == "7" {
			return want
		}
		return nil
	})
	if !errors.Is(err, want) {
		t.Fatalf("got error %v, want %v", err, want)
	}
}
