package volcano_test

import (
	"context"
	_ "embed"
	"fmt"
	"strings"
	"time"

	"github.com/wzshiming/kube-scheduling-perf/test/utils"
	"k8s.io/apimachinery/pkg/api/resource"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"sigs.k8s.io/e2e-framework/klient/decoder"
	"sigs.k8s.io/e2e-framework/klient/k8s/resources"
	"sigs.k8s.io/e2e-framework/klient/wait"
)

//go:embed init.yaml
var initYaml string

//go:embed init_queue.yaml
var initQueueYaml string

//go:embed batch_job.yaml
var batchJobYaml string

//go:embed agent_job.yaml
var agentJobYaml string

type VolcanoProvider struct {
	utils.Options
}

func (p *VolcanoProvider) InitCase(ctx context.Context) error {
	cpuPerQueue, err := resource.ParseQuantity(p.CpuPerQueue)
	if err != nil {
		return err
	}

	memoryPerQueue, err := resource.ParseQuantity(p.MemoryPerQueue)
	if err != nil {
		return err
	}

	cpuCapabilityTotal := utils.TimesQuantity(cpuPerQueue, p.QueueSize+p.ImpactingQueuesSize+p.CriticalQueuesSize).String()
	cpuCapability := ""
	cpuDeserved := ""
	cpuGuarantee := ""

	if p.CpuLendingLimit != "" {
		cpuLendingLimit, err := resource.ParseQuantity(p.CpuLendingLimit)
		if err != nil {
			return err
		}

		cpuCapability = cpuPerQueue.String()
		cpuPerQueue.Sub(cpuLendingLimit)
		cpuDeserved = cpuPerQueue.String()
	} else {
		cpuCapability = cpuPerQueue.String()
	}

	memoryCapabilityTotal := utils.TimesQuantity(memoryPerQueue, p.QueueSize+p.ImpactingQueuesSize+p.CriticalQueuesSize).String()
	memoryCapability := ""
	memoryDeserved := ""
	memoryGuarantee := ""
	if p.MemoryLendingLimit != "" {
		memoryLendingLimit, err := resource.ParseQuantity(p.MemoryLendingLimit)
		if err != nil {
			return err
		}

		memoryCapability = memoryPerQueue.String()
		memoryPerQueue.Sub(memoryLendingLimit)
		memoryDeserved = memoryPerQueue.String()
	} else {
		memoryCapability = memoryPerQueue.String()
	}

	configChanged := false
	err = decoder.DecodeEach(ctx, strings.NewReader(utils.YamlWithArgs(initYaml, map[string]any{
		"gang":                  p.Gang,
		"preemption":            p.Preemption,
		"cpuCapabilityTotal":    cpuCapabilityTotal,
		"memoryCapabilityTotal": memoryCapabilityTotal,
	})), utils.CreateOrUpdateConfigMapsHandler(utils.Resources, &configChanged))
	if err != nil {
		return err
	}

	if configChanged {
		schedulerDeployment := "volcano-scheduler"
		if p.VolcanoMode == "agent" {
			schedulerDeployment = "volcano-agent-scheduler"
		}
		err = utils.RestartDeployment(ctx, utils.Resources, schedulerDeployment, "volcano-system")
		if err != nil {
			return err
		}
	}

	for i := range p.QueueSize {
		err := decoder.DecodeEach(ctx, strings.NewReader(utils.YamlWithArgs(initQueueYaml, map[string]any{
			"name":             fmt.Sprintf("long-term-research-%d", i),
			"cpuCapability":    cpuCapability,
			"memoryCapability": memoryCapability,
			"cpuDeserved":      cpuDeserved,
			"memoryDeserved":   memoryDeserved,
			"cpuGuarantee":     cpuGuarantee,
			"memoryGuarantee":  memoryGuarantee,
		})), decoder.CreateHandler(utils.Resources))
		if err != nil {
			return err
		}
	}

	for i := range p.ImpactingQueuesSize {
		err := decoder.DecodeEach(ctx, strings.NewReader(utils.YamlWithArgs(initQueueYaml, map[string]any{
			"name":             fmt.Sprintf("business-impacting-%d", i),
			"cpuCapability":    cpuCapability,
			"memoryCapability": memoryCapability,
			"cpuDeserved":      cpuDeserved,
			"memoryDeserved":   memoryDeserved,
			"cpuGuarantee":     cpuGuarantee,
			"memoryGuarantee":  memoryGuarantee,
		})), decoder.CreateHandler(utils.Resources))
		if err != nil {
			return err
		}
	}

	for i := range p.CriticalQueuesSize {
		err := decoder.DecodeEach(ctx, strings.NewReader(utils.YamlWithArgs(initQueueYaml, map[string]any{
			"name":             fmt.Sprintf("human-critical-%d", i),
			"cpuCapability":    cpuCapability,
			"memoryCapability": memoryCapability,
			"cpuDeserved":      cpuDeserved,
			"memoryDeserved":   memoryDeserved,
			"cpuGuarantee":     cpuGuarantee,
			"memoryGuarantee":  memoryGuarantee,
		})), decoder.CreateHandler(utils.Resources))
		if err != nil {
			return err
		}
	}
	return nil
}

func (p *VolcanoProvider) AddJobs(ctx context.Context) error {
	steps := []struct {
		queueSize    int
		jobsPerQueue int
		podsPerJob   int
		priority     string
		duration     string
		delay        time.Duration
	}{
		{p.QueueSize, p.JobsSizePerQueue, p.PodsSizePerJob, "long-term-research", p.PodDuration, 0},
		{p.ImpactingQueuesSize, p.ImpactingJobsSizePerQueue, p.ImpactingPodsSizePerJob, "business-impacting", p.ImpactingPodDuration, 5 * time.Second},
		{p.CriticalQueuesSize, p.CriticalJobsSizePerQueue, p.CriticalPodsSizePerJob, "human-critical", p.CriticalPodDuration, 5 * time.Second},
	}

	for _, step := range steps {
		if step.delay > 0 {
			time.Sleep(step.delay)
		}
		err := utils.SubmitConcurrently(ctx, p.SubmitConcurrency, func(yield func(string) error) error {
			for i := range step.queueSize {
				for range step.jobsPerQueue {
					if err := yield(p.renderSingleJob(step.podsPerJob, i, step.priority, step.duration)); err != nil {
						return err
					}
				}
			}
			return nil
		}, func(ctx context.Context, job string) error {
			return decoder.DecodeEach(ctx, strings.NewReader(job), decoder.CreateHandler(utils.Resources))
		})
		if err != nil {
			return err
		}
	}
	return nil
}

func (p *VolcanoProvider) WaitJobsCompleted(ctx context.Context) error {
	expected := p.QueueSize*p.JobsSizePerQueue +
		p.ImpactingQueuesSize*p.ImpactingJobsSizePerQueue +
		p.CriticalQueuesSize*p.CriticalJobsSizePerQueue

	namespacedResources, err := resources.New(utils.Resources.GetConfig())
	if err != nil {
		return err
	}
	namespacedResources.WithNamespace("bench-volcano")

	return wait.For(func(ctx context.Context) (bool, error) {
		jobs := &unstructured.UnstructuredList{}
		if p.VolcanoMode == "agent" {
			jobs.SetAPIVersion("batch/v1")
		} else {
			jobs.SetAPIVersion("batch.volcano.sh/v1alpha1")
		}
		jobs.SetKind("JobList")
		if err := namespacedResources.List(ctx, jobs); err != nil {
			return false, err
		}
		if len(jobs.Items) != expected {
			return false, nil
		}

		for i := range jobs.Items {
			if p.VolcanoMode == "agent" {
				conditions, found, err := unstructured.NestedSlice(jobs.Items[i].Object, "status", "conditions")
				if err != nil {
					return false, err
				}
				completed := false
				for _, condition := range conditions {
					item, ok := condition.(map[string]any)
					if ok && item["type"] == "Complete" && item["status"] == "True" {
						completed = true
						break
					}
				}
				if !found || !completed {
					return false, nil
				}
			} else {
				phase, found, err := unstructured.NestedString(jobs.Items[i].Object, "status", "state", "phase")
				if err != nil {
					return false, err
				}
				if !found || phase != "Completed" {
					return false, nil
				}
			}
		}
		return true, nil
	}, wait.WithInterval(time.Second), wait.WithTimeout(time.Hour))
}

func (p *VolcanoProvider) renderSingleJob(podSize int, queueIndex int, priority string, duration string) string {
	jobYaml := batchJobYaml
	if p.VolcanoMode == "agent" {
		jobYaml = agentJobYaml
	}
	return utils.YamlWithArgs(jobYaml, map[string]any{
		"name":                fmt.Sprintf("%s-%d", priority, queueIndex),
		"queue":               fmt.Sprintf("test-queue-%s-%d", priority, queueIndex),
		"size":                podSize,
		"index":               utils.Index(),
		"cpuRequestPerPod":    p.CpuRequestPerPod,
		"memoryRequestPerPod": p.MemoryRequestPerPod,
		"gang":                p.Gang,
		"priority":            priority,
		"preemption":          p.Preemption,
		"duration":            duration,
	})
}
