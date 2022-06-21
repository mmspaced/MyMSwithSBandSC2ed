# !/usr/bin/env bash

# Print commands to the terminal before execution and stop the script if any error occurs
# set -ex

function waitForPods() {

    set +x
    local expectedPodCount=$1
    local labelSelection=$2
    local sleepSec=10

    n=0
    echo "Do we have $expectedPodCount pods with the label '$labelSelection' yet?"
    actualPodCount=$(kubectl get pod -l $labelSelection -o json | jq ".items | length")
    until [[ $actualPodCount == $expectedPodCount ]]
    do
        n=$((n + 1))
        if [[ $n == 40 ]]
        then
            echo " Give up"
            exit 1
        else
            echo -n "${actualPodCount}!=${expectedPodCount}, sleep $sleepSec..."
            sleep $sleepSec
            echo -n ", retry #$n, "
            actualPodCount=$(kubectl get pod -l $labelSelection -o json | jq ".items | length")
        fi
    done

    set -x
    echo "OK! ($actualPodCount=$expectedPodCount)"
}

minikube delete -p minikube

minikube start --memory 10240 --cpus 4 --disk-size 30g --kubernetes-version=v1.22.3 --driver hyperkit

minikube addons enable ingress
minikube addons enable metrics-server

eval $(minikube docker-env)

# First deploy the resource managers and wait for their pods to become ready
# docker-compose up -d mongodb mysql rabbitmq

./gradlew build && docker-compose build

# kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.7.1/cert-manager.yaml
# kubectl wait --timeout=600s --for=condition=ready pod --all -n cert-manager

# kubectl apply -f kubernetes/services/base/letsencrypt-issuer-staging.yml

# Next deploy the microservices and wait for their pods to become ready
# This is commented out so it can occur after the Istio injection is enabled
# kubectl apply -k kubernetes/services/overlays/prod
# kubectl wait --timeout=600s --for=condition=ready pod --all

# kubectl apply -f kubernetes/services/base/ingress-edge-server-ngrok.yml

# Istio download and configuration

# cd ~/minikube

# curl -L https://istio.io/downloadIstio | sh -

# export PATH=$PWD/bin:$PATH

# Install the demo configuration profile and wait for pods to be ready
istioctl install --set profile=demo -y
kubectl -n istio-system wait --timeout=600s --for=condition=available deployment --all

# Update the Istio configuration to set tracing level to 100%, so all traces are captured
# istioctl install -f ~/Development/SpringBootCloud/MySpringBootProject/kubernetes/enable-all-tracing.yml

# sudo cp /Users/mikemitnick/Development/SpringBootCloud/MySpringBootProject/kubernetes/cert/* /etc/istio/ingressgateway-certs

# Install Istio-specific CRDs into minikube
kubectl apply -f ~/Development/SpringBootCloud/MySpringBootProject/istio-1.13.1/manifests/charts/base/crds/crd-all.gen.yaml
kubectl -n istio-system wait --timeout=600s --for=condition=ready pod --all

# Install Kiali, Prometheus, Grafana, and Jaeger and wait for pods to be ready
kubectl apply -f ~/Development/SpringBootCloud/MySpringBootProject/istio-1.13.1/samples/addons/grafana.yaml
kubectl apply -f ~/Development/SpringBootCloud/MySpringBootProject/istio-1.13.1/samples/addons/jaeger.yaml
kubectl apply -f ~/Development/SpringBootCloud/MySpringBootProject/istio-1.13.1/samples/addons/kiali.yaml
kubectl apply -f ~/Development/SpringBootCloud/MySpringBootProject/istio-1.13.1/samples/addons/prometheus.yaml
kubectl -n istio-system wait --timeout=600s --for=condition=ready pod -l app=kiali

kubectl create namespace hands-on
kubectl config set-context $(kubectl config current-context) --namespace=hands-on
# kubectl label namespace hands-on istio-injection=enabled

openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -keyout kubernetes/cert/tls.key -out kubernetes/cert/tls.crt -subj "/CN=minikube.me/O=minikube.me"
# openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -keyout kubernetes/cert/tls.key -out kubernetes/cert/tls.crt -subj "/CN=minikube.me/O=minikube.me"


# kubectl create secret tls tls-certificate --key kubernetes/cert/tls.key --cert kubernetes/cert/tls.crt

if kubectl -n istio-system get secret istio-ingressgateway-certs > /dev/null ; then
    echo "Secret istio-ingressgateway-certs found, skip creating it..."
else
    echo "Secret istio-ingressgateway-certs not found, creating it..."
    kubectl create -n istio-system secret tls istio-ingressgateway-certs \
        --key ~/Development/SpringBootCloud/MySpringBootProject/kubernetes/cert/tls.key \
        --cert ~/Development/SpringBootCloud/MySpringBootProject/kubernetes/cert/tls.crt
fi

# sudo cp /Users/mikemitnick/Development/SpringBootCloud/MySpringBootProject/kubernetes/cert/* /etc/istio/ingressgateway-certs

# Next deploy the microservices and wait for their pods to become ready
# kubectl config set-context $(kubectl config current-context) --namespace=hands-on

kubectl config set-context $(kubectl config current-context) --namespace=hands-on
cd ~/Development/SpringBootCloud/MySpringBootProject

kubectl create configmap config-repo-auth-server       --from-file=config-repo/application.yml --from-file=config-repo/auth-server.yml --save-config
kubectl create configmap config-repo-gateway           --from-file=config-repo/application.yml --from-file=config-repo/gateway.yml --save-config
kubectl create configmap config-repo-product-composite --from-file=config-repo/application.yml --from-file=config-repo/product-composite.yml --save-config
kubectl create configmap config-repo-product           --from-file=config-repo/application.yml --from-file=config-repo/product.yml --save-config
kubectl create configmap config-repo-recommendation    --from-file=config-repo/application.yml --from-file=config-repo/recommendation.yml --save-config
kubectl create configmap config-repo-review            --from-file=config-repo/application.yml --from-file=config-repo/review.yml --save-config

kubectl create secret generic rabbitmq-server-credentials \
    --from-literal=RABBITMQ_DEFAULT_USER=rabbit-user-dev \
    --from-literal=RABBITMQ_DEFAULT_PASS=rabbit-pwd-dev \
    --save-config

kubectl create secret generic rabbitmq-credentials \
    --from-literal=SPRING_RABBITMQ_USERNAME=rabbit-user-dev \
    --from-literal=SPRING_RABBITMQ_PASSWORD=rabbit-pwd-dev \
    --save-config

kubectl create secret generic rabbitmq-zipkin-credentials \
    --from-literal=RABBIT_USER=rabbit-user-dev \
    --from-literal=RABBIT_PASSWORD=rabbit-pwd-dev \
    --save-config

kubectl create secret generic mongodb-server-credentials \
    --from-literal=MONGO_INITDB_ROOT_USERNAME=mongodb-user-dev \
    --from-literal=MONGO_INITDB_ROOT_PASSWORD=mongodb-pwd-dev \
    --save-config

kubectl create secret generic mongodb-credentials \
    --from-literal=SPRING_DATA_MONGODB_AUTHENTICATION_DATABASE=admin \
    --from-literal=SPRING_DATA_MONGODB_USERNAME=mongodb-user-dev \
    --from-literal=SPRING_DATA_MONGODB_PASSWORD=mongodb-pwd-dev \
    --save-config

kubectl create secret generic mysql-server-credentials \
    --from-literal=MYSQL_ROOT_PASSWORD=rootpwd1 \
    --from-literal=MYSQL_DATABASE=review-db \
    --from-literal=MYSQL_USER=mysql-user-dev \
    --from-literal=MYSQL_PASSWORD=mysql-pwd-dev \
    --save-config

kubectl create secret generic mysql-credentials \
    --from-literal=SPRING_DATASOURCE_USERNAME=mysql-user-dev \
    --from-literal=SPRING_DATASOURCE_PASSWORD=mysql-pwd-dev \
    --save-config

# First deploy the resource managers and wait for their pods to become ready
kubectl apply -f kubernetes/services/overlays/dev/rabbitmq-dev.yml
kubectl apply -f kubernetes/services/overlays/dev/mongodb-dev.yml
kubectl apply -f kubernetes/services/overlays/dev/mysql-dev.yml
kubectl wait --timeout=600s --for=condition=ready pod --all

# This has to take place prior to the deployment of the apps into minikube.  It
# creates a namespace label that instructs Istio to automatically inject Envoy
# sidecar proxies when you deploy your application later.

kubectl label namespace hands-on istio-injection=enabled

# kubectl label namespace hands-on istio-injection=enabled
# Next deploy the microservices and wait for their pods to become ready
kubectl apply -k kubernetes/services/overlays/dev
kubectl wait --timeout=600s --for=condition=ready pod --all

# Inject sidecar proxies into all of the microservices pods + auth-server
kubectl get deployment auth-server product product-composite recommendation review -o yaml | istioctl kube-inject -f - | kubectl apply -f -

waitForPods 5 'version=latest'
kubectl wait --timeout=120s --for=condition=Ready pod --all

# Don't want to launch the dashboard within this script
# istioctl dashboard kiali

# The tunnel needs to be launched in a separate terminal window
# minikube tunnel

read -p "Start the minikube tunnel, then press any key to resume ..."
set -x

export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')

export SECURE_INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')

# export INGRESS_HOST=$(minikube ip)
export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Programatically update the /etc/hosts file entry
# Delete the previous minikube.me entry
sudo sed -i '' '/minikube/d' /etc/hosts
# Append the new minikube.me DNS mapping record to the EOF
echo "$INGRESS_HOST minikube.me" | sudo tee -a /etc/hosts

# Set the GATEWAY_URL environment variable
export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT
echo "GATEWAY_URL = $GATEWAY_URL"

curl -o /dev/null -s -L -w "%{http_code}" http://kiali.istio-system.svc.cluster.local:20001/kiali/

curl -o /dev/null -s -L -w "%{http_code}" http://grafana.istio-system.svc.cluster.local:3000

curl -o /dev/null -s -L -w "%{http_code}" http://tracing.istio-system.svc.cluster.local:80

kubectl get svc -n istio-system

# set +ex