#!/usr/bin/env bash
#
minikube delete -p minikube

minikube start --memory 10240 --cpus 4 --disk-size 30g --kubernetes-version=v1.22.3 --driver virtualbox

eval $(minikube docker-env)

docker-compose up -d mongodb mysql rabbitmq

./gradlew build && docker-compose build

docker tag hands-on/auth-server hands-on/auth-server:v1
docker tag hands-on/config-server hands-on/config-server:v1
docker tag hands-on/gateway hands-on/gateway:v1
docker tag hands-on/product-composite-service hands-on/product-composite-service:v1
docker tag hands-on/product-service hands-on/product-service:v1
docker tag hands-on/recommendation-service hands-on/recommendation-service:v1
docker tag hands-on/review-service hands-on/review-service:v1

kubectl create namespace hands-on
kubectl config set-context $(kubectl config current-context) --namespace=hands-on

kubectl create configmap config-repo --from-file=config-repo/ --save-config

kubectl create secret generic config-server-secrets \
  --from-literal=ENCRYPT_KEY=my-very-secure-encrypt-key \
  --from-literal=SPRING_SECURITY_USER_NAME=prod-usr \
  --from-literal=SPRING_SECURITY_USER_PASSWORD=prod-pwd \
  --save-config
kubectl create secret generic config-client-credentials \
  --from-literal=CONFIG_SERVER_USR=prod-usr \
  --from-literal=CONFIG_SERVER_PWD=prod-pwd \
  --save-config

history -c
history -w

kubectl apply -k kubernetes/services/overlays/prod