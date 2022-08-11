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

cp ./kubernetes/helm/components/rabbitmq/values-dev.yaml ./kubernetes/helm/components/rabbitmq/values.yaml
echo "Copied header authorization credentials for dev environment to the RabbitMQ component's values.yaml file..."

cp .env-dev .env
echo "Copied the dev environment variables to the env file..."

minikube delete -p minikube

minikube start -p minikube --memory='10240m' --cpus='4' --disk-size='30g' --kubernetes-version='v1.24.1' --ports=8080:80 --ports=8443:443 --ports=30080:30080 --ports=30443:30443

minikube addons enable ingress
minikube addons enable metrics-server

helm repo add jetstack https://charts.jetstack.io 
helm repo update
helm install cert-manager jetstack/cert-manager --create-namespace --namespace cert-manager --version v1.3.1 --set installCRDs==true --wait
kubectl get pods --namespace cert-manager

# Use the appropriate docker-compose file for development 
cp docker-compose-dev.yml docker-compose.yml
echo "Copied docker-compose-dev.yml to docker-compose.yml for development"

eval $(minikube docker-env)

########################################################
# Istio does not currently support the Mac M1 processor
########################################################
# istioctl experimental precheck
# istioctl install  --skip-confirmation --set profile=demo --set meshConfig.accessLogFile=/dev/stdout --set meshConfig.accessLogEncoding=JSON 
# kubectl -n istio-system wait --timeout=600s --for=condition=available deployment --all
# kubectl create namespace istio-ingress
# kubectl label namespace istio-ingress istio-injection=enabled --overwrite
# istioctl verify-install

# istio_version=$(istioctl version --short --remote=false)
# kubectl apply -n istio-system -f https://raw.githubusercontent.com/istio/istio/$istio_version/samples/addons/kiali.yaml
# kubectl apply -n istio-system -f https://raw.githubusercontent.com/istio/istio/$istio_version/samples/addons/jaeger.yaml
# kubectl apply -n istio-system -f https://raw.githubusercontent.com/istio/istio/$istio_version/samples/addons/prometheus.yaml
# kubectl apply -n istio-system -f https://raw.githubusercontent.com/istio/istio/$istio_version/samples/addons/grafana.yaml
# kubectl -n istio-system wait --timeout=600s --for=condition=available deployment --all
# kubectl -n istio-system get deploy

# helm upgrade --install istio-hands-on-addons ./kubernetes/helm/environments/istio-system -n istio-system --wait

# kubectl -n istio-system get secret hands-on-certificate
# kubectl -n istio-system get certificate hands-on-certificate

# The tunnel needs to be launched in a separate terminal window
# minikube tunnel
read -p "Start the minikube tunnel, then press any key to resume ..."

# INGRESS_IP=$(kubectl -n istio-system get service istio-ingressgateway -o json | jq -r '.status.loadBalancer.ingress[0].ip')
# echo "INGRESS_IP=${INGRESS_IP}"

INGRESS_IP=127.0.0.1
MINIKUBE_HOST=minikube.me

# MINIKUBE_HOSTS="minikube.me grafana.minikube.me kiali.minikube.me prometheus.minikube.me tracing.minikube.me kibana.minikube.me \
# elasticsearch.minikube.me mail.minikube.me health.minikube.me"

# Programatically update the /etc/hosts file entry
# Delete the previous minikube.me entry
sudo sed -i '' '/minikube/d' /etc/hosts

# Append the new minikube.me DNS mapping record to the EOF
# echo "$INGRESS_IP $MINIKUBE_HOSTS" | sudo tee -a /etc/hosts
echo "$INGRESS_IP $MINIKUBE_HOST" | sudo tee -a /etc/hosts
cat /etc/hosts

# curl -o /dev/null -sk -L -w "%{http_code}\n" https://kiali.minikube.me/kiali/
# curl -o /dev/null -sk -L -w "%{http_code}\n" https://tracing.minikube.me
# curl -o /dev/null -sk -L -w "%{http_code}\n" https://grafana.minikube.me
# curl -o /dev/null -sk -L -w "%{http_code}\n" https://prometheus.minikube.me/graph#/

# eval $(minikube docker-env)

# kubectl delete namespace hands-on
kubectl create namespace hands-on
kubectl config set-context $(kubectl config current-context) --namespace=hands-on

./gradlew build && docker-compose build

# kubectl label namespace hands-on istio-injection=enabled --overwrite
# kubectl apply -f ./kubernetes/hands-on-namespace.yml

for f in ./kubernetes/helm/components/*; do helm dep up $f; done
for f in ./kubernetes/helm/environments/*; do helm dep up $f; done
helm dep ls ./kubernetes/helm/environments/dev-env/

docker pull arm64v8/mysql:8.0.29-oracle
docker pull mongo:latest
docker pull rabbitmq:latest

helm install hands-on-dev-env ./kubernetes/helm/environments/dev-env -n hands-on --create-namespace
kubectl wait --timeout=600s --for=condition=ready pod --all

# Manually inject Istio proxys into an existing Deployment object
# kubectl get deployment hands-on-dev-env -o yaml | istioctl kube-inject -f - | kubectl apply -f -
# kubectl wait --timeout=600s --for=condition=ready pod --all

kubectl get pods


# HOST=$MINIKUBE_HOST PORT=30443 USE_K8S=true ./test-em-all.bash

HOST=minikube.me PORT=8443 USE_K8S=true ./test-em-all.bash
