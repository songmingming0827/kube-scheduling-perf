package utils

import (
	"fmt"
	"os"
	"testing"

	"sigs.k8s.io/e2e-framework/klient/conf"
	"sigs.k8s.io/e2e-framework/klient/k8s/resources"
	"sigs.k8s.io/e2e-framework/pkg/env"
	"sigs.k8s.io/e2e-framework/pkg/envconf"
)

var (
	TestEnv   env.Environment
	EnvConfig *envconf.Config
	Resources *resources.Resources
)

func InitTestMain(m *testing.M) {
	var err error
	path := conf.ResolveKubeConfigFile()
	EnvConfig = envconf.NewWithKubeConfig(path)
	TestEnv = env.NewWithConfig(EnvConfig)

	restConfig := EnvConfig.Client().RESTConfig()
	restConfig.RateLimiter = nil
	restConfig.QPS = 100
	restConfig.Burst = 200

	Resources, err = resources.New(restConfig)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
	os.Exit(TestEnv.Run(m))
}
