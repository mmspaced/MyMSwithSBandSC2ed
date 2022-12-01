#!/usr/bin/env bash

set -e

echo "Start Performance Test: $(date)"

: ${HOST=minikube.me}
: ${PORT=8443}

echo HOST=$HOST
echo PORT=$PORT

ACCESS_TOKEN=$(curl -k https://writer:secret@$HOST:$PORT/oauth2/token -d grant_type=client_credentials -s | jq .access_token -r)
echo WRITER_ACCESS_TOKEN=$ACCESS_TOKEN

AUTH="-H \"Authorization: Bearer $ACCESS_TOKEN\""

echo AUTH=$AUTH

URL="https://minikube.me/product-composite/1 $AUTH"
echo URL=$URL

# siege $AUTH -k https://$HOST:$PORT/product-composite/1 -c1 -d1 -v
siege -H "Authorization: Bearer $ACCESS_TOKEN" -k https://$HOST:$PORT/product-composite/1 -c1 -d1 -v

echo "End, all tests OK: $(date)"
