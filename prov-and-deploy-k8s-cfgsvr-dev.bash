#!/usr/bin/env bash
#
minikube delete -p minikube

minikube start -p minikube --memory='10240m' --cpus='4' --disk-size='30g' --kubernetes-version='v1.23.3' --ports=8080:80 --ports=8443:443 --ports=30080:30080 --ports=30443:30443

minikube addons enable ingress
minikube addons enable metrics-server

# Use the appropriate docker-compose file for development 
cp docker-compose-dev.yml docker-compose.yml
echo "Copied docker-compose-dev.yml to docker-compose.yml for development"

eval $(minikube docker-env)

./gradlew build && docker-compose build

for f in kubernetes/helm/components/*; do helm dep up $f; done
for f in kubernetes/helm/environments/*; do helm dep up $f; done
helm dep ls kubernetes/helm/environments/dev-env/

docker pull arm64v8/mysql:8.0.29-oracle
docker pull mongo:latest
docker pull rabbitmq:latest
docker pull openzipkin/zipkin:latest

helm install hands-on-dev-env kubernetes/helm/environments/dev-env -n hands-on --create-namespace

kubectl config set-context $(kubectl config current-context) --namespace=hands-on

kubectl wait --timeout=600s --for=condition=ready pod --all

# kubectl get pods -o jsonpath='{.items[*].spec.containers[*].image}'
kubectl get pods -o json | jq '.items[].spec.containers[].image'

MINIKUBE_HOST=127.0.0.1

HOST=$MINIKUBE_HOST PORT=30443 USE_K8S=true ./test-em-all.bash
