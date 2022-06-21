#!/usr/bin/env bash
#
minikube delete -p minikube

minikube start --memory 10240 --cpus 4 --disk-size 30g --kubernetes-version=v1.22.3 --driver virtualbox

eval $(minikube docker-env)

./gradlew build && docker-compose build

kubectl create namespace hands-on
kubectl config set-context $(kubectl config current-context) --namespace=hands-on

kubectl create configmap config-repo --from-file=config-repo/ --save-config

kubectl create secret generic config-server-secrets \
  --from-literal=ENCRYPT_KEY=my-very-secure-encrypt-key \
  --from-literal=SPRING_SECURITY_USER_NAME=dev-usr \
  --from-literal=SPRING_SECURITY_USER_PASSWORD=dev-pwd \
  --save-config
kubectl create secret generic config-client-credentials \
  --from-literal=CONFIG_SERVER_USR=dev-usr \
  --from-literal=CONFIG_SERVER_PWD=dev-pwd \
  --save-config
  
kubectl apply -k kubernetes/services/overlays/dev