#!/usr/bin/env bash
#

istioctl x uninstall --purge

minikube delete -p minikube

minikube start -p minikube --memory='10957m' --cpus='4' --disk-size='30g' --kubernetes-version='v1.24.1' --ports=8080:80 --ports=8443:443 --ports=30080:30080 --ports=30443:30443

# minikube addons enable ingress
# minikube addons enable metrics-server

eval $(minikube docker-env)

istioctl experimental precheck
istioctl install  --set profile=demo -y
kubectl label namespace default istio-injection=enabled
kubectl -n istio-system wait --timeout=600s --for=condition=available deployment --all

kubectl apply -f ./istio-1.15.0-beta.0/samples/bookinfo/platform/kube/bookinfo.yaml

kubectl get services

kubectl get pods

