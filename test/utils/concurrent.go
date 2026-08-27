package utils

import (
	"context"
	"fmt"
	"sync"
)

// SubmitConcurrently renders submissions in the caller and processes them with
// a bounded worker pool.
func SubmitConcurrently(
	ctx context.Context,
	concurrency int,
	produce func(yield func(string) error) error,
	process func(context.Context, string) error,
) error {
	if concurrency < 1 {
		return fmt.Errorf("submission concurrency must be at least 1")
	}

	workerCtx, cancel := context.WithCancel(ctx)
	defer cancel()

	jobs := make(chan string, concurrency)
	var workers sync.WaitGroup
	var firstError sync.Once
	var processError error

	fail := func(err error) {
		firstError.Do(func() {
			processError = err
			cancel()
		})
	}

	for range concurrency {
		workers.Add(1)
		go func() {
			defer workers.Done()
			for {
				select {
				case <-workerCtx.Done():
					return
				case job, ok := <-jobs:
					if !ok {
						return
					}
					if err := process(workerCtx, job); err != nil {
						fail(err)
						return
					}
				}
			}
		}()
	}

	produceError := produce(func(job string) error {
		select {
		case jobs <- job:
			return nil
		case <-workerCtx.Done():
			return workerCtx.Err()
		}
	})
	if produceError != nil {
		cancel()
	}
	close(jobs)
	workers.Wait()

	if processError != nil {
		return processError
	}
	if produceError != nil {
		return produceError
	}
	return ctx.Err()
}
