# !/usr/bin/env bash

# Print commands to the terminal before execution and stop the script if any error occurs
# set -ex

# minikube delete -p minikube

# minikube start --memory 10240 --cpus 4 --disk-size 30g --kubernetes-version=v1.22.3 --driver virtualbox

# minikube addons enable ingress

eval $(minikube docker-env)

# First deploy the resource managers and wait for their pods to become ready
docker-compose up -d mongodb mysql rabbitmq

./gradlew build && docker-compose build

docker tag hands-on/auth-server               hands-on/auth-server:v1
docker tag hands-on/product-composite-service hands-on/product-composite-service:v1 
docker tag hands-on/product-service           hands-on/product-service:v1
docker tag hands-on/recommendation-service    hands-on/recommendation-service:v1
docker tag hands-on/review-service            hands-on/review-service:v1

kubectl create namespace hands-on
kubectl config set-context $(kubectl config current-context) --namespace=hands-on

kubectl create configmap config-repo-auth-server       --from-file=config-repo/application.yml --from-file=config-repo/auth-server.yml --save-config
kubectl create configmap config-repo-gateway           --from-file=config-repo/application.yml --from-file=config-repo/gateway.yml --save-config
kubectl create configmap config-repo-product-composite --from-file=config-repo/application.yml --from-file=config-repo/product-composite.yml --save-config
kubectl create configmap config-repo-product           --from-file=config-repo/application.yml --from-file=config-repo/product.yml --save-config
kubectl create configmap config-repo-recommendation    --from-file=config-repo/application.yml --from-file=config-repo/recommendation.yml --save-config
kubectl create configmap config-repo-review            --from-file=config-repo/application.yml --from-file=config-repo/review.yml --save-config

kubectl create secret generic rabbitmq-server-credentials \
    --from-literal=RABBITMQ_DEFAULT_USER=rabbit-user-prod \
    --from-literal=RABBITMQ_DEFAULT_PASS=rabbit-pwd-prod \
    --save-config

kubectl create secret generic rabbitmq-credentials \
    --from-literal=SPRING_RABBITMQ_USERNAME=rabbit-user-prod \
    --from-literal=SPRING_RABBITMQ_PASSWORD=rabbit-pwd-prod \
    --save-config

kubectl create secret generic rabbitmq-zipkin-credentials \
    --from-literal=RABBIT_USER=rabbit-user-prod \
    --from-literal=RABBIT_PASSWORD=rabbit-pwd-prod \
    --save-config

kubectl create secret generic mongodb-server-credentials \
    --from-literal=MONGO_INITDB_ROOT_USERNAME=mongodb-user-prod \
    --from-literal=MONGO_INITDB_ROOT_PASSWORD=mongodb-pwd-prod \
    --save-config

kubectl create secret generic mongodb-credentials \
    --from-literal=SPRING_DATA_MONGODB_AUTHENTICATION_DATABASE=admin \
    --from-literal=SPRING_DATA_MONGODB_USERNAME=mongodb-user-prod \
    --from-literal=SPRING_DATA_MONGODB_PASSWORD=mongodb-pwd-prod \
    --save-config

kubectl create secret generic mysql-server-credentials \
    --from-literal=MYSQL_ROOT_PASSWORD=rootpwd1 \
    --from-literal=MYSQL_DATABASE=review-db \
    --from-literal=MYSQL_USER=mysql-user-prod \
    --from-literal=MYSQL_PASSWORD=mysql-pwd-prod \
    --save-config

kubectl create secret generic mysql-credentials \
    --from-literal=SPRING_DATASOURCE_USERNAME=mysql-user-prod \
    --from-literal=SPRING_DATASOURCE_PASSWORD=mysql-pwd-prod \
    --save-config

kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.7.1/cert-manager.yaml
kubectl wait --timeout=600s --for=condition=ready pod --all -n cert-manager

kubectl apply -f kubernetes/services/base/letsencrypt-issuer-staging.yml
kubectl apply -f kubernetes/services/base/letsencrypt-issuer-prod.yml

# Next deploy the microservices and wait for their pods to become ready
kubectl apply -k kubernetes/services/overlays/prod
kubectl wait --timeout=600s --for=condition=ready pod --all

# kubectl apply -f kubernetes/services/base/ingress-edge-server-ngrok.yml

# set +ex