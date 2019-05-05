# Makefile containing the basic presubmit and integration tests, running inside a kind node or docker image.


# Run the istio install and tests. Assumes KUBECONFIG is pointing to a valid cluster.
# This should run inside a container and using KIND, to reduce dependency on host or k8s environment.
# It can also be used directly on the host against a real k8s cluster.
run-all-tests: install-full \
	run-test.integration.kube.presubmit run-simple run-simple-strict run-bookinfo run-prometheus-operator-config-test

# Tests running against 'micro' environment - just citadel + pilot + ingress
# TODO: also add 'nano' - pilot + ingress without citadel, some users are using this a-la-carte option
run-micro-tests: install-crds install-base install-ingress run-simple run-simple-strict



E2E_ARGS=--skip_setup --use_local_cluster=true --istio_namespace=${ISTIO_NS}

SIMPLE_AUTH ?= false

# The simple test from istio/istio integration, in permissive mode
# Will kube-inject and test the ingress and service-to-service
run-simple-base: ${TMPDIR}
	mkdir -p  ${GOPATH}/out/logs
	kubectl create ns ${NS} || true
	# Global default may be strict or permissive - make it explicit for this ns
	kubectl -n ${NS} apply -f test/k8s/mtls_${MODE}.yaml
	kubectl -n ${NS} apply -f test/k8s/sidecar-local.yaml
	kubectl label ns ${NS} istio-injection=disabled --overwrite
	(set -o pipefail; cd ${GOPATH}/src/istio.io/istio; \
	 go test -v -timeout 25m ./tests/e2e/tests/simple -args \
	     --auth_enable=${SIMPLE_AUTH} \
         --egress=false \
         --ingress=false \
         --rbac_enable=false \
         --cluster_wide \
         --skip_setup \
         --use_local_cluster=true \
         --istio_namespace=${ISTIO_NS} \
         --namespace=${NS} \
         ${SIMPLE_EXTRA} \
         --istioctl=${ISTIOCTL_BIN} \
           2>&1 | tee ${GOPATH}/out/logs/$@.log)

run-simple:
	$(MAKE) run-simple-base MODE=permissive NS=simple

# Simple test, strict mode
run-simple-strict:
	$(MAKE) run-simple-base MODE=strict NS=simple-strict SIMPLE_AUTH=true

run-bookinfo-demo:
	kubectl create ns bookinfo-demo || true
	kubectl -n bookinfo-demo apply -f test/k8s/mtls_permissive.yaml
	kubectl -n bookinfo-demo apply -f test/k8s/sidecar-local.yaml
	(cd ${GOPATH}/src/istio.io/istio; make e2e_bookinfo_run ${TEST_FLAGS} \
		E2E_ARGS="${E2E_ARGS} --namespace=bookinfo-demo")

# Simple bookinfo install and curl command
run-bookinfo:
	kubectl create ns bookinfo || true
	echo ${BASE} ${GOPATH}
	# Bookinfo test
	#kubectl label namespace bookinfo istio-env=${ISTIO_NS} --overwrite
	kubectl -n bookinfo apply -f test/k8s/mtls_permissive.yaml
	kubectl -n bookinfo apply -f test/k8s/sidecar-local.yaml
	SKIP_CLEANUP=1 ISTIO_CONTROL=${ISTIO_NS} INGRESS_NS=${ISTIO_NS} SKIP_DELETE=1 SKIP_LABEL=1 bin/test.sh ${GOPATH}/src/istio.io/istio

# Simple fortio install and curl command
#run-fortio:
#	kubectl apply -f

run-mixer:
	kubectl create ns mixertest || true
	kubectl -n mixertest apply -f test/k8s/mtls_permissive.yaml
	kubectl -n mixertest apply -f test/k8s/sidecar-local.yaml
	(cd ${GOPATH}/src/istio.io/istio; make e2e_mixer_run ${TEST_FLAGS} \
		E2E_ARGS="${E2E_ARGS} --namespace=mixertest")

INT_FLAGS ?= -istio.test.hub ${HUB} -istio.test.tag ${TAG} -istio.test.pullpolicy IfNotPresent \
 -p 1 -istio.test.env kube --istio.test.kube.config ${KUBECONFIG} --istio.test.ci --istio.test.nocleanup \
 --istio.test.kube.deploy=false -istio.test.kube.systemNamespace ${ISTIO_NS} -istio.test.kube.minikube

# Integration tests create and delete istio-system
# Need to be fixed to use new installer
# Requires an environment with telemetry installed
run-test.integration.kube:
	export TMPDIR=${GOPATH}/out/tmp
	mkdir -p ${GOPATH}/out/tmp
	#(cd ${GOPATH}/src/istio.io/istio; \
	#	$(GO) test -v ${T} ./tests/integration/... ${INT_FLAGS})
	kubectl -n default apply -f test/k8s/mtls_permissive.yaml
	kubectl -n default apply -f test/k8s/sidecar-local.yaml
	# Test uses autoinject
	#kubectl label namespace default istio-env=${ISTIO_NS} --overwrite
	(cd ${GOPATH}/src/istio.io/istio; TAG=${TAG} make test.integration.kube \
		CI=1 T="-v" K8S_TEST_FLAGS="--istio.test.kube.minikube --istio.test.kube.systemNamespace ${ISTIO_NS} \
		 --istio.test.nocleanup --istio.test.kube.deploy=false ")

run-test.integration.kube.presubmit:
	export TMPDIR=${GOPATH}/out/tmp
	mkdir -p ${GOPATH}/out/tmp ${GOPATH}/out/linux_amd64/release/ ${GOPATH}/out/logs/
	set -o pipefail; \
	cd ${GOPATH}/src/istio.io/istio; \
		${GO} test -p 1 -v \
			istio.io/istio/tests/integration/echo istio.io/istio/tests/integration/... \
    --istio.test.kube.deploy=false --istio.test.kube.minikube  --istio.test.nocleanup \
	--istio.test.kube.istioNamespace istio-system \
	--istio.test.kube.configNamespace ${ISTIO_NS} \
	--istio.test.kube.telemetryNamespace ${ISTIO_NS} \
	--istio.test.kube.policyNamespace ${ISTIO_NS} \
	--istio.test.kube.ingressNamespace ${ISTIO_NS} \
	--istio.test.kube.egressNamespace ${ISTIO_NS} \
	--istio.test.ci -timeout 30m \
    --istio.test.select +presubmit \
 	--istio.test.env kube \
	--istio.test.kube.config ${KUBECONFIG} \
	--istio.test.hub=${HUB} \
	--istio.test.tag=${TAG} \
	--istio.test.pullpolicy=IfNotPresent  2>&1 | tee ${GOPATH}/out/logs/$@.log

run-stability:
	 ISTIO_ENV=${ISTIO_NS} bin/iop test stability ${GOPATH}/src/istio.io/tools/perf/stability/allconfig ${IOP_OPTS}

run-mysql:
	 ISTIO_ENV=${ISTIO_NS} bin/iop mysql mysql ${BASE}/test/mysql ${IOP_OPTS}
	 ISTIO_ENV=${ISTIO_NS} bin/iop mysqlplain mysqlplain ${BASE}/test/mysql ${IOP_OPTS} --set mtls=false --set Name=plain

# This test currently only validates the correct config generation and install in API server.
# When prom operator config moves out of alpha, this should be incorporated in the other tests
# and removed.
run-prometheus-operator-config-test: PROM_OPTS="--set prometheus.createPrometheusResource=true"
run-prometheus-operator-config-test: install-prometheus-operator install-prometheus-operator-config
	if [ "$$(kubectl -n ${ISTIO_NS} get servicemonitors -o name | wc -l)" -ne "7" ]; then echo "Failure to find ServiceMonitor resouces!"; return 1; fi
	kubectl -n ${ISTIO_NS} wait pod/prometheus-prometheus-0 --for=condition=Ready --timeout=${WAIT_TIMEOUT}