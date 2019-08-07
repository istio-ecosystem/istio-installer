# Targets for testing the installer in 'minimal' mode. Both configs install only pilot and optional ingress or
# manual-injected sidecars.

# Security is not enabled - this can be used for users who have ipsec or other secure VPC, or don't need the
# security features. It is also intended to verify that Istio can work without citadel for a-la-carte modes.

test-noauth: run-build-cluster run-build-minimal run-build-ingress
	$(MAKE) KIND_CLUSTER=${KIND_CLUSTER}-noauth maybe-clean maybe-prepare sync
	$(MAKE) KIND_CLUSTER=${KIND_CLUSTER}-noauth kind-run TARGET="run-test-noauth-micro"
	$(MAKE) KIND_CLUSTER=${KIND_CLUSTER}-noauth kind-run TARGET="run-test-knative"

# Run a test with the smallest/simplest install possible
run-test-noauth-micro:
	kubectl apply -k kustomize/cluster --prune -l istio=cluster

	kubectl apply -k kustomize/minimal --prune -l release=istio-system-istio-discovery
	# TODO: add upgrade/downgrade tests from 1.2.x for minimal profile
	kubectl apply -k kustomize/istio-ingress --prune -l release=istio-system-istio-ingress

	kubectl wait deployments istio-pilot istio-ingressgateway -n istio-system --for=condition=available --timeout=${WAIT_TIMEOUT}

	kubectl apply -f test/kind/ingress-service.yaml

	# Verify that we can kube-inject using files ( there is no injector in this config )
	kubectl create ns simple-micro || true

	istioctl kube-inject -f test/simple/servicesToBeInjected.yaml \
		-n simple-micro \
		--meshConfigFile test/simple/mesh.yaml \
		--valuesFile test/simple/values.yaml \
		--injectConfigFile istio-control/istio-autoinject/files/injection-template.yaml \
	 | kubectl apply -n simple-micro -f -

	kubectl wait deployments echosrv-deployment-1 -n simple-micro --for=condition=available --timeout=${WAIT_TIMEOUT}

	# Verify ingress and pilot are happy
	# The 'simple' fortio has a rewrite rule - so /fortio/fortio/ is the real UI
	#curl localhost:30080/fortio/fortio/ -v


# Installs minimal istio (pilot + ingressgateway) to support knative serving.
# Then installs a simple service and waits for the route to be ready.
run-test-knative:
	kubectl apply -k kustomize/cluster --prune -l istio=cluster

	# Install Knative CRDs (istio-crds applied via install-crds)
	# Using serving seems to be flaky - no matches for kind "Image" in version "caching.internal.knative.dev/v1alpha1"
	kubectl apply --selector=knative.dev/crd-install=true --filename test/knative/crds.yaml
	kubectl wait --for=condition=Established -f test/knative/crds.yaml

	# Install pilot, ingress - using a kustomization that installs them in istio-micro instead of istio-system
	kubectl apply -k test/knative
	kubectl wait deployments istio-ingressgateway istio-pilot -n istio-micro --for=condition=available --timeout=${WAIT_TIMEOUT}
	kubectl apply -f test/kind/ingress-service-micro.yaml

	kubectl apply --filename test/knative/serving.yaml

	kubectl wait deployments webhook controller activator autoscaler \
	  -n knative-serving --for=condition=available --timeout=${WAIT_TIMEOUT}

	kubectl apply --filename test/knative/service.yaml

	# The route may take some small period of time to be create, so we cannot just directly wait on it
	# Longer timneout - default is 240s
	kubectl wait routes helloworld-go --for=condition=ready --timeout=600s

	# Verify that ingress, pilot and knative are all happy
	#curl localhost:30090/hello -v -H Host:helloworld-go.default.example.com

run-test-noauth-full:
	echo "Skipping - only micro profile in scope, will use telemetry-lite"
