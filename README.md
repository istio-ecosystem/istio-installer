[![CircleCI](https://circleci.com/gh/istio/installer.svg?style=shield)](https://circleci.com/gh/istio/installer)
[![Build Status](https://badge.buildkite.com/a22a72134042949c314994a6d0e0abe0281444541d25d2d105.svg)](https://buildkite.com/istio/istio-installer)
[![Mergify Status](https://gh.mergify.io/badges/istio/installer.png?style=cut)](https://mergify.io)

# Istio Installer

Istio installer is a modular, 'a-la-carte' installer for Istio. It is based on a
fork of the Istio helm templates, refactored to increase modularity and isolation.

Goals:
- Improve upgrade experience: users should be able to gradually roll upgrades, with proper
canary deployments for Istio components. It should be possible to deploy a new version while keeping the
stable version in place and gradually migrate apps to the new version.

- More flexibility: the new installer allows multiple 'environments', allowing applications to select
a set of control plane settings and components. While the entire mesh respects the same APIs and config,
apps may target different 'environments' which contain different instances and variants of Istio.

- Better security: separate Istio components reside in different namespaces, allowing different teams or
roles to manage different parts of Istio. For example, a security team would maintain the
root CA and policy, a telemetry team may only have access to Mixer-telemetry and Prometheus,
and a different team may maintain the control plane components (which are highly security sensitive).

The install is organized in 'environments' - each environment consists of a set of components
in different namespaces that are configured to work together. Regardless of 'environment',
workloads can talk with each other and obey the Istio configuration resources, but each environment
can use different Istio versions and different configuration defaults.

`istioctl kube-inject` or the automatic sidecar injector are used to select the environment.
In the case of the sidecar injector, the namespace label `istio-env: <NAME_OF_ENV>` is used instead
of the conventional `istio-injected: true`. The name of the environment is defined as the namespace
where the corresponding control plane components (config, discovery, auto-injection) are running.
In the examples below, by default this is the `istio-control` namespace. Pod annotations can also
be used to select a different 'environment'.

# Installing

The new installer is intended to be modular and very explicit about what is installed. It has
far more steps than the Istio installer - but each step is smaller and focused on a specific
feature, and can be performed by different people/teams at different times.

It is strongly recommended that different namespaces are used, with different service accounts.
In particular access to the security-critical production components (root CA, policy, control)
should be locked down and restricted.  The new installer allows multiple instances of
policy/control/telemetry - so testing/staging of new settings and versions can be performed
by a different role than the prod version.

The intended users of this repo are users running Istio in production who want to select, tune
and understand each binary that gets deployed, and select which combination to use.

Note: each component can be installed in parallel with an existing Istio 1.0 or 1.1 install in
`istio-system`. The new components will not interfere with existing apps, but can interoperate
and it is possible to gradually move apps from Istio 1.0/1.1 to the new environments and
across environments ( for example canary -> prod )

Note: there are still some cluster roles that may need to be fixed, most likely cluster permissions
will need to move to the security component.

# Everything is Optional

Each component in the new installer is optional. Users can install the component defined in the new installer,
use the equivalent component in `istio-system`, configured with the official installer, or use a different
version or implementation.

For example you may use your own Prometheus and Grafana installs, or you may use a specialized/custom
certificate provisioning tool, or use components that are centrally managed and running in a different cluster.

This is a work in progress - building on top of the multi-cluster installer.

As an extreme, the goal is to be possible to run Istio workloads in a cluster without installing any Istio component
in that cluster. Currently the minimum we require is the security provider (node agent or citadel).

# Namespaces

The new installer recommends isolating components in different namespaces with different service accounts and access.

Recommended mode:

Singleton:
- `istio-system`: root CA and cert provisioning components.
- `istio-cni`: optional CNI (avoids requiring root/netadmin from workload pods)

Multi-environment components:
- `istio-control`: config, discovery, auto-inject. All impact the generated config including enforcement of policies
and secure naming.
- `istio-telemetry`: mixer, kiali, tracing providers, grafana, prometheus. Custom install of prometheus, grafana can
be used instead in dedicated namespaces.
- `istio-policy`
- `istio-gateways` - production domains should be in a separate namespace, to restrict access. It is possible to
segregate gateways by the team that control access to the domain. Access to the gateway namespace provides access
to certificates and control over domain delegation. The optional egress gateway provides control over outbound
traffic.

In addition, it is recommended to have a second set of the multi-environment components to use
for canary/testing new versions. In this doc we will use an environment based on the `istio-master` namespace:
- `istio-master`: config, discovery, etc
- `istio-telemetry-master`
- `istio-gateway-master`
- `istio-policy-master`
...


# Installing

For each component, there are 2 styles of installing, using 'helm + tiller' or '`helm template` + `kubectl apply --prune`'.

Using `kubectl --prune` is recommended:

```bash

helm template --namespace $NAMESPACE -n $COMPONENT $CONFIGDIR -f global.yaml | \
   kubectl apply -n $NAMESPACE --prune -l release=$COMPONENT -f -

```

Using helm:

```bash
helm upgrade --namespace $NAMESPACE -n $COMPONENT $CONFIGDIR -f global.yaml
```

The doc will use the `iop $NAMESPACE $COMPONENT $CONFIGDIR` helper from `env.sh` - which is the equivalent
to the commands above.

In the instructions below, `$IBASE` refers to the working tree of this repo.

## Common options

TODO: replicas, cpu allocs, etc.

## Install Istio CRDs

This is the first step of the install. Please do not remove or edit any CRD - config currently requires
all CRDs to be present. On each upgrade it is recommended to reapply the file, to make sure
you get all CRDs.  CRDs are separated by release and by component type in the CRD directory.

Istio has strong integration with certmanager.  Some operators may want to keep their current certmanager
CRDs in place and not have Istio modify them.  In this case, it is necessary to apply CRD files individually.

```bash
 kubectl apply -k github.com/istio/installer/crds
```

or

```bash
 kubectl apply -f crds/files
```

## Install Security

Security should be installed in `istio-system`, since it needs access to the root CA.
For upgrades from the official installer, it is recommended to install the security component in
`istio-system`, install the other components in different namespaces, migrate all workloads - and
at the end uninstall the official installer, and lock down istio-system.

This is currently required if any mTLS is used. In future other Spifee implementations can be used, and
it is possible to use other tools that create the expected certificates for Istio.

```bash
iop istio-system citadel $IBASE/security/citadel
```

**Important options**: the `dnsCerts` list allows associating DNS certs with specific service accounts.
This should be used if you plan to use Galley or Sidecar injector in different namespaces.
By default it supports `istio-control`, `istio-master` namespaces used in the examples.

Access to the security namespace and `istio-system` should be highly restricted.

## Install Istio-CNI

This is an optional step - CNI must run in a dedicated namespace, it is a 'singleton' and extremely
security sensitive. Access to the CNI namespace must be highly restricted.

**NOTE:** The environment variable `ISTIO_CLUSTER_ISGKE` is assumed to be set to `true` if the cluster
is a GKE cluster.

```bash
ISTIO_CNI_ARGS=
# TODO: What k8s data can we use for this check for whether GKE?
if [[ "${ISTIO_CLUSTER_ISGKE}" == "true" ]]; then
    ISTIO_CNI_ARGS="--set cniBinDir=/home/kubernetes/bin"
fi
bin/iop istio-cni istio-cni $IBASE/istio-cni/ ${ISTIO_CNI_ARGS}
```

TODO. It is possible to add Istio-CNI later, and gradually migrate.

## Install Control plane

The control plane contains 3 components.

### Config (Galley)

This can be run in any other cluster having the CRDs configured via CI/CD systems or other sync mechanisms.
It should not be run in 'secondary' clusters, where the configs are not replicated.

Galley provides config access and validation. Only one environment should enable validation - it is not
currently supported in multiple namespaces.

```bash
     iop istio-control istio-config $IBASE/istio-control/istio-config --set configValidation=true

    # Second Galley, using master version of istio
    TAG=master-latest-daily HUB=gcr.io/istio-release iop istio-master istio-config-master $IBASE/istio-control/istio-config
```

Other MCP providers can be used - currently the address and credentials need to match what galley is using.

Discovery, Policy and Telemetry components will need to be configured with the address of the config
server - either in the local cluster or in a central cluster.


### Discovery (Pilot)

This can run in any cluster. A mesh should have at least one cluster should run Pilot or equivalent XDS server,
and it is recommended to have Pilot running in each region and in multiple availability zones for multi cluster.

```bash
    iop istio-control istio-discovery $IBASE/istio-control/istio-discovery

    TAG=master-latest-daily HUB=gcr.io/istio-release iop istio-master istio-discovery-master $IBASE/istio-control/istio-discovery \
                --set policy.enable=false \
               --set global.istioNamespace=istio-master \
               --set global.configNamespace=istio-master \
               --set global.telemetryNamespace=istio-telemetry-master \
               --set global.policyNamespace=istio-policy-master

```

### Auto-injection

This is optional - `istioctl kube-inject` can be used instead.

If installed, namespaces can select the injector by setting the `istio-env` label on the namespace.

Only one auto-injector environment should have `enableNamespacesByDefault=true`, which will apply that environment
to any namespace without an explicit `istio-env` label.

If `istio-system` has set `enableNamespaceByDefault` you must set `istio-inject: disabled` label to prevent
istio-system from taking over. In this case, it is recommended to first install `istio-control` autoinject with
the default disabled, test it, and move the default from `istio-system` to `istio-control`.


```bash
    # ENABLE_CNI is set to true if istio-cni is installed
    iop istio-control istio-autoinject $IBASE/istio-control/istio-autoinject --set sidecarInjectorWebhook.enableNamespacesByDefault=true \
        --set istio_cni.enabled=${ENABLE_CNI}

    # Second auto-inject using master version of istio
    # Notice the different options
    TAG=master-latest-daily HUB=gcr.io/istio-release iop istio-master istio-autoinject-master $IBASE/istio-control/istio-autoinject \
             --set global.istioNamespace=istio-master

```

## Gateways

A cluster may use multiple Gateways, each with a different load balancer IP, domains and certificates.

Since the domain certificates are stored in the gateway namespace, it is recommended to keep each
gateway in a dedicated namespace and restrict access.

For large-scale gateways it is optionally possible to use a dedicated pilot in the gateway namespace.


## K8S Ingress

To support K8S ingress we currently use a separate namespace. In Istio 1.1, this requires using a dedicated
Pilot instance in the ingress namespace. This will be fixed in future releases.

Note that running a dedicated Pilot for ingress/gateways is supported and recommended for very large sites,
but in the case of K8S ingress it is currently required.

```bash
    iop istio-ingress istio-ingress $IBASE/gateways/istio-ingress --set global.istioNamespace=istio-master
```

## Telemetry

```bash
    iop istio-telemetry istio-grafana $IBASE/istio-telemetry/grafana/ --set global.istioNamespace=istio-master

    iop istio-telemetry istio-mixer $IBASE/istio-telemetry/mixer-telemetry/ --set global.istioNamespace=istio-master

    iop istio-telemetry istio-prometheus $IBASE/istio-telemetry/prometheus/ --set global.istioNamespace=istio-master

    iop istio-telemetry istio-tracing $IBASE/istio-telemetry/tracing/ --set global.istioNamespace=istio-master
```

## Policy

```bash
    iop istio-policy istio-policy $IBASE/istio-policy/ --set global.istioNamespace=istio-master
```

## Egress

```bash
    iop istio-egress istio-egress $IBASE/gateways/istio-egress/ --set global.istioNamespace=istio-master
```


## Other components

### Kiali

```bash
    iop istio-telemetry istio-kiali $IBASE/istio-telemetry/kiali/ --set global.istioNamespace=istio-master
```

## Additional test templates

A number of helm test setups are general-purpose and should be installable in any cluster, to confirm
Istio works properly and allow testing the specific install.

