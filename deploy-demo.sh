#!/bin/sh
# Deploy app monitoring stack and prometheus-adapter in namespace 'app-monitoring-1'
oc new-project app-monitoring-1
oc apply -f OperatorGroup.yml -n app-monitoring-1
oc apply -f PrometheusOperator.yml -n app-monitoring-1
oc apply -f Prometheus.yml -n app-monitoring-1
oc apply -f ServiceMonitor.yml -n app-monitoring-1

oc adm policy add-cluster-role-to-user view system:serviceaccount:app-monitoring-1:prometheus-k8s
oc apply -f prometheus-adapter-roles.yml
oc apply -f prometheus-adapter-apiservice.yml -n app-monitoring-1
oc apply -f prometheus-adapter-cm.yml -n app-monitoring-1
oc apply -f prometheus-adapter-deploy.yml -n app-monitoring-1

# Deploy instrumented apps and HPA 'apps-1'
oc new-project apps-1
oc apply -f podinfo-deploy.yml -n apps-1
oc apply -f podinfo-svc.yml -n apps-1
oc expose svc podinfo
oc apply -f b2m-nodejs-deploy.yml -n apps-1
oc apply -f b2m-nodejs-svc.yml -n apps-1
oc expose svc b2m-nodejs
oc apply -f hpa-podinfo.yml -n apps-1
oc apply -f hpa-b2m-nodejs.yml -n apps-1

oc expose svc prometheus-operated  -n app-monitoring-1
