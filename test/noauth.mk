# Targets for testing the installer in 'no tls' mode.
# This can be used for users who have ipsec or other secure VPC, or don't need the security features.
# It is intended to verify that Istio can work without citadel for a-la-carte modes.

# Included from the top level makefile, to keep things a bit more modular.

# The tests run in a separate Kind cluster, ${KIND_CLUSTER}-noauth - otherwise citadel would create the certs.
# Only a subset of features are supported - currently autoinject and validation are off until installer is able
# to provision the certs they need to register with k8s.

# Also used to test 'controlPlaneSecurity=OFF', for cases where citadel is not installed.

# Will create a KIND cluster and run the tests in the docker image running KIND
# You can also run the targets directly, against a real cluster: make run-test-noauth-full

test-noauth:
	$(MAKE) KIND_CLUSTER=${KIND_CLUSTER}-noauth maybe-clean maybe-prepare sync
	$(MAKE) KIND_CLUSTER=${KIND_CLUSTER}-noauth kind-run TARGET="run-test-noauth-micro"
	$(MAKE) KIND_CLUSTER=${KIND_CLUSTER}-noauth kind-run TARGET="run-test-noauth-full"

# Run a test without authentication, minimal possible install. The cluster should have no certs (so we can
# confirm that all the 'off' is respected.
# Will install 2 control planes, one with only discovery + ingress ( micro ), one with galley, discovery, telemetry
run-test-noauth-micro: install-crds
	bin/iop ${ISTIO_NS}-micro istio-discovery ${BASE}/istio-control/istio-discovery ${IOP_OPTS} \
		--set global.controlPlaneSecurityEnabled=false --set useMCP=false --set plugins="health"
	kubectl wait deployments istio-pilot -n ${ISTIO_NS}-micro --for=condition=available --timeout=${WAIT_TIMEOUT}
	bin/iop ${ISTIO_NS}-micro istio-ingress ${BASE}/gateways/istio-ingress --set global.istioNamespace=${ISTIO_NS}-micro \
	 	${IOP_OPTS} --set global.controlPlaneSecurityEnabled=false
	kubectl wait deployments ingressgateway -n ${ISTIO_NS}-micro --for=condition=available --timeout=${WAIT_TIMEOUT}

	# Verify that we can kube-inject using files ( there is no injector in this config )
	kubectl create ns simple-micro || true
	istioctl kube-inject -f test/simple/servicesToBeInjected.yaml \
		-n simple-micro \
		--meshConfigFile test/simple/mesh.yaml \
		--valuesFile test/simple/values.yaml \
		--injectConfigFile istio-control/istio-autoinject/files/injection-template.yaml \
	 | kubectl apply -n simple-micro -f -

# TODO: pass meshConfigFile, injectConfigFile, valuesFile to test, or skip the kube-inject and do it manually (better)
# Test won't work otherwise
#	$(MAKE) run-simple-base MODE=permissive NS=simple-micro ISTIO_NS=${ISTIO_NS}-micro \
#		SIMPLE_EXTRA="--kube_inject_configmap ${GOPATH}/src/github.com/istio-ecosystem/istio-installer/istio-control/istio-autoinject/files/injection-template.yaml"

# Galley, Pilot, Ingress, Telemetry (separate ns)
run-test-noauth-full: install-crds
	bin/iop ${ISTIO_NS} istio-config ${BASE}/istio-control/istio-config ${IOP_OPTS} \
		--set global.controlPlaneSecurityEnabled=false --set configValidation=false

	bin/iop ${ISTIO_NS} istio-discovery ${BASE}/istio-control/istio-discovery ${IOP_OPTS} \
    	--set global.controlPlaneSecurityEnabled=false --set plugins="health"
	kubectl wait deployments istio-pilot istio-galley -n ${ISTIO_NS} --for=condition=available --timeout=${WAIT_TIMEOUT}
	bin/iop ${ISTIO_NS} istio-ingress ${BASE}/gateways/istio-ingress --set global.istioNamespace=${ISTIO_NS} ${IOP_OPTS} \
		 --set global.controlPlaneSecurityEnabled=false
	kubectl wait deployments ingressgateway -n ${ISTIO_NS} --for=condition=available --timeout=${WAIT_TIMEOUT}
	bin/iop ${ISTIO_NS} istio-telemetry ${BASE}/istio-telemetry/mixer-telemetry ${IOP_OPTS} \
         --set global.controlPlaneSecurityEnabled=false
	bin/iop ${ISTIO_NS} istio-prometheus ${BASE}/istio-telemetry/prometheus/ --set global.istioNamespace=${ISTIO_NS} ${IOP_OPTS} \
		 --set global.controlPlaneSecurityEnabled=false
	bin/iop ${ISTIO_NS} istio-mixer ${BASE}/istio-telemetry/mixer-telemetry/ --set global.istioNamespace=${ISTIO_NS} ${IOP_OPTS} \
		--set global.controlPlaneSecurityEnabled=false

	kubectl wait deployments istio-telemetry prometheus -n ${ISTIO_NS} --for=condition=available --timeout=${WAIT_TIMEOUT}

	# TODO: Autoinject requires certs - they can be created by a tool, see b/...
	# bin/iop ${ISTIO_NS} istio-autoinject ${BASE}/istio-control/istio-autoinject \
	#	--set global.istioNamespace=${ISTIO_NS} ${IOP_OPTS} --set global.controlPlaneSecurityEnabled=false
	#kubectl wait deployments istio-sidecar-injector -n ${ISTIO_NS} --for=condition=available --timeout=${WAIT_TIMEOUT}
	#$(MAKE) run-simple
