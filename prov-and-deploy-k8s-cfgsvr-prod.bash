#!/usr/bin/env bash
#
minikube delete -p minikube

minikube start -p minikube --memory='10240m' --cpus='4' --disk-size='30g' --kubernetes-version='v1.23.3' --ports=8080:80 --ports=8443:443 --ports=30080:30080 --ports=30443:30443

minikube addons enable ingress
minikube addons enable metrics-server

# Use the appropriate docker-compose file for production 
cp docker-compose-prod.yml docker-compose.yml
echo "Copied docker-compose-prod.yml to docker-compose.yml for production"

eval $(minikube docker-env)

./gradlew build && docker-compose build

docker tag hands-on/auth-server hands-on/auth-server:v1
docker tag hands-on/config-server hands-on/config-server:v1
docker tag hands-on/gateway hands-on/gateway:v1
docker tag hands-on/product-composite-service hands-on/product-composite-service:v1
docker tag hands-on/product-service hands-on/product-service:v1
docker tag hands-on/recommendation-service hands-on/recommendation-service:v1
docker tag hands-on/review-service hands-on/review-service:v1

for f in kubernetes/helm/components/*; do helm dep up $f; done
for f in kubernetes/helm/environments/*; do helm dep up $f; done
helm dep ls kubernetes/helm/environments/prod-env/

docker pull arm64v8/mysql:8.0.29-oracle
docker pull mongo:latest
docker pull rabbitmq:latest
docker pull openzipkin/zipkin:latest

helm install hands-on-prod-env kubernetes/helm/environments/prod-env -n hands-on --create-namespace

kubectl config set-context $(kubectl config current-context) --namespace=hands-on

kubectl wait --timeout=600s --for=condition=ready pod --all

# kubectl get pods -o jsonpath='{.items[*].spec.containers[*].image}'
kubectl get pods -o json | jq '.items[].spec.containers[].image'

CONFIG_SERVER_USR=prod-usr CONFIG_SERVER_PWD=prod-pwd HOST=127.0.0.1 PORT=30443 USE_K8S=true ./test-em-all.bash
