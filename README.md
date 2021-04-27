# Horizontal Pod Autoscaling using custom Prometheus metrics

Deploy the demo stack with `deploy-demo.sh`. 

Expected outcome:
- Prometheus Operator and Prometheus Adapter deployed in `app-monitoring-1` namespace.
- Two applications instrumented with prometheus client library and two corresponding HPA definitions deployed in `apps-1` namespace.
- Prometheus configured in order to monitor deployed apps
- Prometheus adapter configured in order to expose selected metrics via `custom.metrics.k8s.io` API.

Wait ~3-5 min. and then verify:

- The monitoring stack is up and running:

```sh
$ oc get po -n app-monitoring-1
NAME                                   READY   STATUS    RESTARTS   AGE
prometheus-adapter-576788b988-979v5    1/1     Running   7          56m
prometheus-app-monitoring-prom-0       3/3     Running   1          56m
prometheus-operator-78759d86d4-ndl9h   1/1     Running   0          56m
```

- Apps are running:
```sh
$ oc get po -n apps-1
NAME                          READY   STATUS    RESTARTS   AGE
b2m-nodejs-56cd9f97cb-qx5kf   1/1     Running   0          62m
podinfo-776fcdb8cc-67pdq      1/1     Running   0          34m
podinfo-776fcdb8cc-6msm4      1/1     Running   0          62m
```

- Metrics are exposed via `custom.metrics.k8s.io` API:

```sh
$ oc get --raw "/apis/custom.metrics.k8s.io/v1beta1"|jq .
{
  "kind": "APIResourceList",
  "apiVersion": "v1",
  "groupVersion": "custom.metrics.k8s.io/v1beta1",
  "resources": [
    {
      "name": "namespaces/http_requests_per_second",
      "singularName": "",
      "namespaced": false,
      "kind": "MetricValueList",
      "verbs": [
        "get"
      ]
    },
    {
      "name": "pods/http_requests_per_second",
      "singularName": "",
      "namespaced": true,
      "kind": "MetricValueList",
      "verbs": [
        "get"
      ]
    },
    {
      "name": "services/http_requests_per_second",
      "singularName": "",
      "namespaced": true,
      "kind": "MetricValueList",
      "verbs": [
        "get"
      ]
    }
  ]
}
```

- HPA shows proper values:

```sh
$ oc get hpa -n apps-1
NAME         REFERENCE               TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
b2m-nodejs   Deployment/b2m-nodejs   <unknown>/200   1         5         1          84s
podinfo      Deployment/podinfo      142m/10         2         10        2          86s
```
> The current value `<unknown>` for b2m-nodejs HPA is expected because we haven't generated any `/checkout` requests to this app yet. Podinfo HPA shows current value because it counts small rate of requests coming from the liveness probe.
>
## Scenario 1 - scale `podinfo` for high request rate.

Collect external URL for `podinfo` app:

```sh
$ oc get route podinfo -n apps-1
NAME      HOST/PORT                                  PATH   SERVICES   PORT   TERMINATION   WILDCARD
podinfo   podinfo-apps-1.apps.rs13.os.fyre.ibm.com          podinfo    http                 None
```

HPA `podinfo` will scale podinfo replicas for request rate higher than 10/sec.
Generate high request rate with `hey` (https://github.com/rakyll/hey)

```sh
hey -n 10000 -c 100 http://podinfo-apps-1.apps.rs13.os.fyre.ibm.com
```

In the second session check status of the HPA for `podinfo`.
After about 1 minute HPA should start to scale `podinfo` replicas:

```sh
$ oc get hpa podinfo -n apps-1
NAME         REFERENCE               TARGETS     MINPODS   MAXPODS   REPLICAS   AGE
podinfo      Deployment/podinfo      14983m/10   2         10        10         85m
```

```sh
$ oc get po -n apps-1
NAME                          READY   STATUS    RESTARTS   AGE
b2m-nodejs-56cd9f97cb-qx5kf   1/1     Running   0          86m
podinfo-776fcdb8cc-67pdq      1/1     Running   0          58m
podinfo-776fcdb8cc-6msm4      1/1     Running   0          86m
podinfo-776fcdb8cc-djm6t      1/1     Running   0          2m46s
podinfo-776fcdb8cc-gffzj      1/1     Running   0          2m46s
podinfo-776fcdb8cc-q7tlv      1/1     Running   0          2m31s
podinfo-776fcdb8cc-rjpvw      1/1     Running   0          2m31s
podinfo-776fcdb8cc-rlhw4      1/1     Running   0          2m46s
podinfo-776fcdb8cc-twv5l      1/1     Running   0          2m46s
podinfo-776fcdb8cc-vc9w7      1/1     Running   0          3m1s
podinfo-776fcdb8cc-w8llm      1/1     Running   0          3m1s
```

## Scenario 2 - scale `b2m-nodejs` for high 90th percentile of http request duration

Collect external URL for `b2m-nodejs` app:

```sh
$ oc get route b2m-nodejs
NAME         HOST/PORT                                     PATH   SERVICES     PORT   TERMINATION   WILDCARD
b2m-nodejs   b2m-nodejs-apps-1.apps.rs13.os.fyre.ibm.com          b2m-nodejs   http                 None
```

In our scenario we calculate p90 value for requests duration (90% of http requests to b2m-nodejs app in the last 1 minute are faster than this value) and HPA will scale `b2m-nodejs` replicas if this value is greater than 200 ms.
Why percentiles are better for response time than averages: https://www.dynatrace.com/news/blog/why-averages-suck-and-percentiles-are-great/

In the second session generate some requests that are slower than usual:

```sh
while [ 1 ];do curl http://b2m-nodejs-apps-1.apps.rs13.os.fyre.ibm.com/checkout?delay=200; sleep 1;done
```
The above should generate requests with response time between 200ms and 300ms.

After about 1 minute HPA should start to scale `b2m-nodejs` replicas:

```sh
$ oc get hpa b2m-nodejs
NAME         REFERENCE               TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
b2m-nodejs   Deployment/b2m-nodejs   285833m/200   1         5         3          104m
```

```sh
$ oc get po
NAME                          READY   STATUS    RESTARTS   AGE
b2m-nodejs-56cd9f97cb-lwmc4   1/1     Running   0          2m
b2m-nodejs-56cd9f97cb-qx5kf   1/1     Running   0          104m
b2m-nodejs-56cd9f97cb-w9pfs   1/1     Running   0          60s
```