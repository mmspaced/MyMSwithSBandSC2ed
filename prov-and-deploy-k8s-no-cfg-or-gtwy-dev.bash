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
# minikube addons enable kong
# minikube addons enable metrics-server

helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager --create-namespace --namespace cert-manager --version v1.3.1 --set installCRDs==true --wait
kubectl get pods --namespace cert-manager

# Use the appropriate docker-compose file for development 
cp docker-compose-dev.yml docker-compose.yml
echo "Copied docker-compose-dev.yml to docker-compose.yml for development"

INGRESS_IP=127.0.0.1
MINIKUBE_HOST=minikube.me

# The following statements to update the etc/hosts file are unnecessary because we are running Minikube with the default Docker
# driver and, therefore, the ingress IP address is always 127.0.0.1 

# Programatically update the /etc/hosts file entry
# Delete the previous minikube.me entry
# sudo sed -i '' '/minikube/d' /etc/hosts

# Append the new minikube.me DNS mapping record to the EOF
# echo "$INGRESS_IP $MINIKUBE_HOSTS" | sudo tee -a /etc/hosts
# echo "$INGRESS_IP $MINIKUBE_HOST" | sudo tee -a /etc/hosts
# cat /etc/hosts

eval $(minikube docker-env)

kubectl delete namespace hands-on
kubectl create namespace hands-on
kubectl config set-context $(kubectl config current-context) --namespace=hands-on

kubectl apply -f ./kubernetes/kuma-hands-on-namespace.yml
kubectl wait --timeout=600s --for=condition=ready pod --all

./gradlew build && docker-compose build

for f in ./kubernetes/helm/components/*; do helm dep up $f; done
for f in ./kubernetes/helm/environments/*; do helm dep up $f; done
helm dep ls ./kubernetes/helm/environments/dev-env/

# docker pull arm64v8/mysql:8.0.29-oracle
docker pull arm64v8/mariadb:latest
docker pull mongo:latest
docker pull rabbitmq:latest

# helm install hands-on-dev-env ./kubernetes/helm/environments/dev-env -n hands-on --create-namespace
helm install hands-on-dev-env ./kubernetes/helm/environments/dev-env -n hands-on
kubectl wait --timeout=600s --for=condition=ready pod --all

kubectl get pods

# The tunnel needs to be launched in a separate terminal window
read -r -p "Start the minikube tunnel, then press any key to resume ..."

kumactl install control-plane | kubectl apply -f -
sleep 5

# Look at the pods running with the kuma-system namespace
kubectl get pods -n kuma-system
sleep 10

# Delete the pods so that Minikube will restart them and the sidecar container will be added to each pod.
kubectl delete pods --all -n hands-on
sleep 20

# Verify that there are now two containers (app artifact and sidecar) running in each pod
kubectl get pods -n hands-on
#
## Port-forward the Kuma control plane service so that you can access the Kuma GUI at http://localhost:5681/gui
read -r -p "Type kubectl port-forward service/kuma-control-plane -n kuma-system 5681 in a separate terminal session "
#
## Deploy Kong Ingress for Kubernetes using the kong-ingress-dbless.yml file in this directory
kubectl apply -f ./kong-ingress-dbless.yml --wait
sleep 30
#kubectl apply -f ./kubernetes/kong-ingress.yml
#sleep 10
#
## Port-forward the product-composite service so that test-em-all can access at http://localhost:8443
#read -r -p "Type kubectl port-forward svc/product-composite 8443:80 in a separate terminal session "
#
# Inspect the data plane proxies in the mesh
kumactl inspect dataplanes
#
## Validate that the Kong proxy is running as a pod with 2 containers in the kong namespace
#kubectl get pods -n hands-on
#
## Verify that the external IP is established for the Kong proxy
#echo "Verify that the external IP is established for the Kong proxy"
#kubectl get services -n hands-on
#
#curl -i http://127.0.0.1:80
#
#echo " "
#
#KONG_PROXY_EXTERNAL_IP=$(kubectl get -o jsonpath="{.status.loadBalancer.ingress[0].ip}" service -n hands-on kong-proxy)
#echo "KONG_PROXY_EXTERNAL_IP = $KONG_PROXY_EXTERNAL_IP"
#
kumactl install observability | kubectl apply -f -
sleep 20
#
kubectl apply -f ./kubernetes/kuma-metrics-logging-tracing.yml
kubectl wait --timeout=600s --for=condition=ready pod --all

# Port-forward Grafana so that you can access on http://localhost:3000
read -r -p "Type kubectl port-forward svc/grafana -n mesh-observability 3000:80 in a separate terminal session "

HOST=minikube.me PORT=8443 USE_K8S=true ./test-em-all.bash
