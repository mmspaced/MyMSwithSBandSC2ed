# !/usr/bin/env bash

kubectl create namespace first-attempts
kubectl config set-context $(kubectl config current-context) --namespace=first-attempts