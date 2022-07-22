#!/usr/bin/env bash
#
echo "Copying application.yml to all the Helm components configuration directories..."
cp ./config-repo/application.yml ./kubernetes/helm/components/auth-server/config-repo/
cp ./config-repo/application.yml ./kubernetes/helm/components/product/config-repo/
cp ./config-repo/application.yml ./kubernetes/helm/components/product-composite/config-repo/
cp ./config-repo/application.yml ./kubernetes/helm/components/recommendation/config-repo/
cp ./config-repo/application.yml ./kubernetes/helm/components/review/config-repo/

echo "Copying the component specific config files to all the Helm components configuration directories..."
cp ./config-repo/auth-server.yml ./kubernetes/helm/components/auth-server/config-repo/
cp ./config-repo/product.yml ./kubernetes/helm/components/product/config-repo/
cp ./config-repo/product-composite.yml ./kubernetes/helm/components/product-composite/config-repo/
cp ./config-repo/recommendation.yml ./kubernetes/helm/components/recommendation/config-repo/
cp ./config-repo/review.yml ./kubernetes/helm/components/review/config-repo/

minikube delete -p minikube

minikube start -p minikube --memory='10240m' --cpus='4' --disk-size='30g' --kubernetes-version='v1.23.3' --ports=8080:80 --ports=8443:443 --ports=30080:30080 --ports=30443:30443

minikube addons enable ingress
minikube addons enable metrics-server

helm repo add jetstack https://charts.jetstack.io 
helm repo update
helm install cert-manager jetstack/cert-manager --create-namespace --namespace cert-manager --version v1.3.1 --set installCRDs==true --wait
kubectl get pods --namespace cert-manager
# kubectl get certificates -w --output-watch-events

# Use the appropriate docker-compose file for development 
cp docker-compose-dev.yml docker-compose.yml
echo "Copied docker-compose-dev.yml to docker-compose.yml for development"

eval $(minikube docker-env)

kubectl create namespace hands-on

kubectl config set-context $(kubectl config current-context) --namespace=hands-on

./gradlew build && docker-compose build

for f in kubernetes/helm/components/*; do helm dep up $f; done
for f in kubernetes/helm/environments/*; do helm dep up $f; done
helm dep ls kubernetes/helm/environments/dev-env/

docker pull arm64v8/mysql:8.0.29-oracle
docker pull mongo:latest
docker pull rabbitmq:latest
docker pull openzipkin/zipkin:latest

helm install hands-on-dev-env kubernetes/helm/environments/dev-env -n hands-on --create-namespace

kubectl wait --timeout=600s --for=condition=ready pod --all

# kubectl get pods -o jsonpath='{.items[*].spec.containers[*].image}'
kubectl get pods -o json | jq '.items[].spec.containers[].image'

MINIKUBE_HOST=127.0.0.1

# HOST=$MINIKUBE_HOST PORT=30443 USE_K8S=true ./test-em-all.bash

HOST=minikube.me PORT=8443 USE_K8S=true ./test-em-all.bash
