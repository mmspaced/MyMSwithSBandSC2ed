# !/usr/bin/env bash

minikube delete -p minikube

# minikube start --memory 10240 --cpus 4 --disk-size 30g --kubernetes-version=v1.22.3 --driver virtualbox
minikube start --memory 10240 --cpus 4 --disk-size 30g --kubernetes-version=v1.22.3 --driver hyperkit

eval $(minikube docker-env)
cd ~/Development/SpringBootCloud/MySpringBootProject

# First deploy the resource managers and wait for their pods to become ready
# docker-compose up -d mongodb mysql rabbitmq

./gradlew build && docker-compose build

kubectl create namespace hands-on

# Istio download and configuration

cd ~/minikube

curl -L https://istio.io/downloadIstio | sh -

# export PATH=$PWD/bin:$PATH

# Install the demo configuration profile and wait for pods to be ready
cd ~/minikube/istio-1.13.0
istioctl install --set profile=demo -y
kubectl -n istio-system wait --timeout=600s --for=condition=available deployment --all

# Next deploy the microservices and wait for their pods to become ready
kubectl config set-context $(kubectl config current-context) --namespace=hands-on
cd ~/Development/SpringBootCloud/MySpringBootProject

kubectl apply -k kubernetes/services/overlays/dev
kubectl wait --timeout=600s --for=condition=ready pod --all

kubectl get deployment auth-server product product-composite recommendation review -o yaml | istioctl kube-inject -f - | kubectl apply -f -

waitForPods 5 'version=latest'
kubectl wait --timeout=120s --for=condition=Ready pod --all