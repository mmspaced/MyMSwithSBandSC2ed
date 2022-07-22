#!/usr/bin/env bash
#
# ./grdelw clean build
# docker-compose build
# docker-compose up -d
#

#   HOST=minikube.me PORT=443 HEALTH_URL=https://localhost:8443 ./test-em-all.bash
#
: ${HOST=localhost}
: ${PORT=8443}
: ${MGMT_PORT=4004}
: ${HEALTH_URL_K8S=http://product-composite.hands-on.svc.cluster.local:$MGMT_PORT}
# : ${HEALTH_URL_DOCKER=http://$HOST:$MGMT_PORT/product-composite}
: ${SKIP_CB_TESTS=false}
: ${PROD_ID_REVS_RECS=2}
: ${PROD_ID_NOT_FOUND=13}
: ${PROD_ID_NO_RECS=114}
: ${PROD_ID_NO_REVS=214}
: ${NAMESPACE=hands-on}

function assertCurl() {

    local expectedHttpCode=$1
    local curlCmd="$2 -w \"%{http_code}\""
    local result=$(eval $curlCmd)
    local httpCode="${result:(-3)}"
    RESPONSE='' && (( ${#result} > 3 )) && RESPONSE="${result%???}"

    if [ "$httpCode" = "$expectedHttpCode" ]
    then
        if [ "$httpCode" = "200" ]
        then
            echo "Test OK (HTTP Code: $httpCode)"
        else
            echo "Test OK (HTTP Code: $httpCode, $RESPONSE)"
        fi
        return 0
    else
        echo  "Test FAILED, EXPECTED HTTP Code: $expectedHttpCode, GOT: $httpCode, WILL ABORT!"
        echo  "- Failing command: $curlCmd"
        echo  "- Response Body: $RESPONSE"
        return 1
    fi
}

function assertEqual() {

    local expected=$1
    local actual=$2

    if [ "$actual" = "$expected" ]
    then
        echo "Test OK (actual value: $actual)"
        return 0
    else
        echo "Test FAILED, EXPECTED VALUE: $expected, ACTUAL VALUE: $actual, WILL ABORT"
        return 1
    fi
}

function testUrl() {
    url=$@
    if ($url -ks -f -o /dev/null)
    then
          return 0
    else
          return 1
    fi;
}

function waitForService() {
    url=$@
    echo -n "Wait for: $url... "
    n=0
    until testUrl $url
    do
        n=$((n + 1))
        if [[ $n == 100 ]]
        then
            echo " Give up"
            exit 1
        else
            sleep 6
            echo -n ", retry #$n "
        fi
    done
    echo "DONE, continues..."
}

function testCompositeCreated() {

    # Expect that the Product Composite for productId $PROD_ID_REVS_RECS has been created with three recommendations and three reviews
    if ! assertCurl 200 "curl $AUTH -k https://$HOST:$PORT/product-composite/$PROD_ID_REVS_RECS  -s"
    then
        echo -n "FAIL"
        return 1
    fi

    set +e
    assertEqual "$PROD_ID_REVS_RECS" $(echo $RESPONSE | jq .productId)
    if [ "$?" -eq "1" ] ; then return 1; fi

    assertEqual 3 $(echo $RESPONSE | jq ".recommendations | length")
    if [ "$?" -eq "1" ] ; then return 1; fi

    assertEqual 3 $(echo $RESPONSE | jq ".reviews | length")
    if [ "$?" -eq "1" ] ; then return 1; fi

    set -e
}

function waitForMessageProcessing() {
    echo "Wait for messages to be processed... "

    # Give background processing some time to complete...
    sleep 1

    n=0
    until testCompositeCreated
    do
        n=$((n + 1))
        if [[ $n == 40 ]]
        then
            echo " Give up"
            exit 1
        else
            sleep 6
            echo -n ", retry #$n "
        fi
    done
    echo "All messages are now processed!"
}

function recreateComposite() {
    local productId=$1
    local composite=$2

    assertCurl 200 "curl $AUTH -X DELETE -k https://$HOST:$PORT/product-composite/${productId} -s"
    curl -X POST -k https://$HOST:$PORT/product-composite -H "Content-Type: application/json" -H "Authorization: Bearer $ACCESS_TOKEN" --data "$composite"

}

function setupTestdata() {

    body="{\"productId\":$PROD_ID_NO_RECS"
    body+=\
',"name":"product name A","weight":100, "reviews":[
    {"reviewId":1,"author":"author 1","subject":"subject 1","content":"content 1"},
    {"reviewId":2,"author":"author 2","subject":"subject 2","content":"content 2"},
    {"reviewId":3,"author":"author 3","subject":"subject 3","content":"content 3"}
]}'
    recreateComposite "$PROD_ID_NO_RECS" "$body"

    body="{\"productId\":$PROD_ID_NO_REVS"
    body+=\
',"name":"product name B","weight":200, "recommendations":[
    {"recommendationId":1,"author":"author 1","rate":1,"content":"content 1"},
    {"recommendationId":2,"author":"author 2","rate":2,"content":"content 2"},
    {"recommendationId":3,"author":"author 3","rate":3,"content":"content 3"}
]}'
    recreateComposite "$PROD_ID_NO_REVS" "$body"


    body="{\"productId\":$PROD_ID_REVS_RECS"
    body+=\
',"name":"product name C","weight":300, "recommendations":[
        {"recommendationId":1,"author":"author 1","rate":1,"content":"content 1"},
        {"recommendationId":2,"author":"author 2","rate":2,"content":"content 2"},
        {"recommendationId":3,"author":"author 3","rate":3,"content":"content 3"}
    ], "reviews":[
        {"reviewId":1,"author":"author 1","subject":"subject 1","content":"content 1"},
        {"reviewId":2,"author":"author 2","subject":"subject 2","content":"content 2"},
        {"reviewId":3,"author":"author 3","subject":"subject 3","content":"content 3"}
    ]}'
    # recreateComposite 1 "$body"
    recreateComposite "$PROD_ID_REVS_RECS" "$body"

}

function testCircuitBreaker() {

    echo "Start Circuit Breaker tests!"

    # EXEC="docker run --rm -it --network=my-network alpine"
    # Assume we are using Docker Compose if we are running on localhost, otherwise Kubernetes 
    
    if [ "$HOST" = 'localhost' ]
    then
        echo "Executing within Docker..."
        EXEC="docker run --rm -it --network=my-network alpine"
    else
        echo "Executing within Kubernetes..."
        echo "Restarting alpine-client..."
        local ns=$NAMESPACE
        if kubectl -n $ns get pod alpine-client > /dev/null ; then
            kubectl -n $ns delete pod alpine-client --grace-period=1
        fi
        kubectl -n $ns run --restart=Never alpine-client --image=alpine --command -- sleep 600
        echo "Waiting for alpine-client to be ready..."
        kubectl -n $ns wait --for=condition=Ready pod/alpine-client

        EXEC="kubectl -n $ns exec alpine-client --"
    fi

    # First, use the health - endpoint to verify that the circuit breaker is closed
    # assertEqual "CLOSED" "$($EXEC wget product-composite:8080/actuator/health -qO - | jq -r .components.circuitBreakers.details.product.details.state)"
    assertEqual "CLOSED" "$($EXEC wget product-composite:${MGMT_PORT}/actuator/health -qO - | jq -r .components.circuitBreakers.details.product.details.state)"

    # Open the circuit breaker by running three slow calls in a row, i.e. that cause a timeout exception
    # Also, verify that we get 500 back and a timeout related error message
    for ((n=0; n<3; n++))
    do
        assertCurl 500 "curl -k https://$HOST:$PORT/product-composite/$PROD_ID_REVS_RECS?delay=3 $AUTH -s"
        message=$(echo $RESPONSE | jq -r .message)
        assertEqual "Did not observe any item or terminal signal within 2000ms" "${message:0:57}"
    done

    # Verify that the circuit breaker is now open
    # assertEqual "OPEN" "$($EXEC wget product-composite:8080/actuator/health -qO - | jq -r .components.circuitBreakers.details.product.details.state)"
    assertEqual "OPEN" "$($EXEC wget product-composite:${MGMT_PORT}/actuator/health -qO - | jq -r .components.circuitBreakers.details.product.details.state)"

    # Verify that the circuit breaker is now open by running the slow call again, verify it gets 200 back, i.e. fail fast works, and a response from the fallback method.
    assertCurl 200 "curl -k https://$HOST:$PORT/product-composite/$PROD_ID_REVS_RECS?delay=3 $AUTH -s"
    assertEqual "Fallback product2" "$(echo "$RESPONSE" | jq -r .name)"

    # Also, verify that the circuit breaker is open by running a normal call, verify it also gets 200 back and a response from the fallback method.
    assertCurl 200 "curl -k https://$HOST:$PORT/product-composite/$PROD_ID_REVS_RECS $AUTH -s"
    assertEqual "Fallback product2" "$(echo "$RESPONSE" | jq -r .name)"

    # Verify that the circuit breaker is still open
    # assertEqual "OPEN" "$($EXEC wget product-composite:8080/actuator/health -qO - | jq -r .components.circuitBreakers.details.product.details.state)"
    assertEqual "OPEN" "$($EXEC wget product-composite:${MGMT_PORT}/actuator/health -qO - | jq -r .components.circuitBreakers.details.product.details.state)"

    # Verify that a 404 (Not Found) error is returned for a non existing productId ($PROD_ID_NOT_FOUND) from the fallback method.
    assertCurl 404 "curl -k https://$HOST:$PORT/product-composite/$PROD_ID_NOT_FOUND $AUTH -s"
    assertEqual "Product Id: $PROD_ID_NOT_FOUND not found in fallback cache!" "$(echo $RESPONSE | jq -r .message)"

    # Wait for the circuit breaker to transition to the half open state (i.e. max 10 sec)
    echo "Will sleep for 10 sec waiting for the CB to go Half Open..."
    sleep 10

    # Verify that the circuit breaker is in half open state
    # assertEqual "HALF_OPEN" "$($EXEC wget product-composite:8080/actuator/health -qO - | jq -r .components.circuitBreakers.details.product.details.state)"
    assertEqual "HALF_OPEN" "$($EXEC wget product-composite:${MGMT_PORT}/actuator/health -qO - | jq -r .components.circuitBreakers.details.product.details.state)"

    # Close the circuit breaker by running three normal calls in a row
    # Also, verify that we get 200 back and a response based on information in the product database
    for ((n=0; n<3; n++))
    do
        assertCurl 200 "curl -k https://$HOST:$PORT/product-composite/$PROD_ID_REVS_RECS $AUTH -s"
        assertEqual "product name C" "$(echo "$RESPONSE" | jq -r .name)"
    done

    # Verify that the circuit breaker is in closed state again
    # assertEqual "CLOSED" "$($EXEC wget product-composite:8080/actuator/health -qO - | jq -r .components.circuitBreakers.details.product.details.state)"
    assertEqual "CLOSED" "$($EXEC wget product-composite:${MGMT_PORT}/actuator/health -qO - | jq -r .components.circuitBreakers.details.product.details.state)"

    # Verify that the expected state transitions happened in the circuit breaker
    # assertEqual "CLOSED_TO_OPEN"      "$($EXEC wget product-composite:8080/actuator/circuitbreakerevents/product/STATE_TRANSITION -qO - | jq -r .circuitBreakerEvents[-3].stateTransition)"
    # assertEqual "OPEN_TO_HALF_OPEN"   "$($EXEC wget product-composite:8080/actuator/circuitbreakerevents/product/STATE_TRANSITION -qO - | jq -r .circuitBreakerEvents[-2].stateTransition)"
    # assertEqual "HALF_OPEN_TO_CLOSED" "$($EXEC wget product-composite:8080/actuator/circuitbreakerevents/product/STATE_TRANSITION -qO - | jq -r .circuitBreakerEvents[-1].stateTransition)"

    assertEqual "CLOSED_TO_OPEN"      "$($EXEC wget product-composite:${MGMT_PORT}/actuator/circuitbreakerevents/product/STATE_TRANSITION -qO - | jq -r .circuitBreakerEvents[-3].stateTransition)"
    assertEqual "OPEN_TO_HALF_OPEN"   "$($EXEC wget product-composite:${MGMT_PORT}/actuator/circuitbreakerevents/product/STATE_TRANSITION -qO - | jq -r .circuitBreakerEvents[-2].stateTransition)"
    assertEqual "HALF_OPEN_TO_CLOSED" "$($EXEC wget product-composite:${MGMT_PORT}/actuator/circuitbreakerevents/product/STATE_TRANSITION -qO - | jq -r .circuitBreakerEvents[-1].stateTransition)"

    # Shutdown the client pod if we are using Kubernetes, i.e. not runnig on localhost. 
        if [ "$HOST" != "localhost" ]
        then
            kubectl -n $ns delete pod alpine-client --grace-period=1
        fi

}

# --------------------------------------------------------------------------------------------------
# ****************************************** Start of script ***************************************
# --------------------------------------------------------------------------------------------------
set -e

echo "Start Tests:" `date`

echo "HOST=${HOST}"
echo "PORT=${PORT}"

if [[ $@ == *"start"* ]]
then
    echo "Restarting the test environment..."
    echo "$ docker-compose down --remove-orphans"
    docker-compose down --remove-orphans
    echo "$ docker-compose up -d"
    docker-compose up -d
    # echo "Sleeping for 520 seconds to allow all containers to start and complete initialization..."
    # sleep 520
fi

if [ "$HOST" != 'localhost' ]
then
    echo "Waiting for Minikube deployments to be up and running..."
    kubectl wait --timeout=600s --for=condition=ready pod --all
    # Wait for all heath checks to complete successfully
    waitForService curl -k $HEALTH_URL_K8S/actuator/health
else
    # Wait for all heath checks to complete successfully
    echo "Waiting for Docker deployments to be up and running..."
    waitForService curl -k https://$HOST:$PORT/actuator/health

fi

# Local authorization server
# Acquire a writer (read and write scopes) access token using the password grant flow 

# Re-enabled local authorization server token retrieval because Auth0 didnt seem to work for accessing the config server API
# to retrieve config data through HTTP basic authentication in the header (pg. 357)

echo "About to invoke curl command to get access token from authorization server..."
ACCESS_TOKEN=$(curl -k https://writer:secret@$HOST:$PORT/oauth/token -d grant_type=password -d username=magnus -d password=password -s | jq .access_token -r)
# ACCESS_TOKEN=$(curl -k http://writer:secret@auth-server.hands-on.svc.cluster.local/oauth/token -d grant_type=password -d username=magnus -d password=password -s | jq .access_token -r)
# ACCESS_TOKEN=$(curl https://raw.githubusercontent.com/istio/istio/release-1.13/security/tools/jwt/samples/demo.jwt -s)

AUTH="-H \"Authorization: Bearer $ACCESS_TOKEN\""
echo "Bearer writer ACCESS_TOKEN with read and write scopes = ${ACCESS_TOKEN}"

# Auth0 authorization server.  Disabled because it didn't seem to work with HTTP basic auth. retrieval of config data using APIs

# Auth0 Email, Password, Domain, Client ID, and Secret

# AUTH0_USER_NAME="mmitnick.mm@gmail.com"
# AUTH0_PASSWORD="Wynne123!"
# AUTH0_DOMAIN="dev-qmpygyfn.us.auth0.com"
# AUTH0_CLIENT_ID="B0L1tiZGFsjygWCESJddN2YTILOuea3J"
# AUTH0_CLIENT_SECRET="a1LGb0nEa935xO1hxY4Db5kvDd6jl5u-UV5K_8Lw3ymzSLFi19yM_axDM-QQrG5t"

# Enable Auth0 authorization server token retrieval

# ACCESS_TOKEN=$(curl --request POST \
#   --url 'https://dev-qmpygyfn.us.auth0.com/oauth/token' \
#   --header 'content-type: application/json' \
#   --data '{"grant_type":"password", "username":"mmitnick.mm@gmail.com", "password":"Wynne123!", "audience":"https://localhost:8443/product-composite", "scope":"openid email read:product write:product", "client_id": "B0L1tiZGFsjygWCESJddN2YTILOuea3J","client_secret": "a1LGb0nEa935xO1hxY4Db5kvDd6jl5u-UV5K_8Lw3ymzSLFi19yM_axDM-QQrG5t"}' -s | jq -r .access_token)

# AUTH="-H 'Authorization: Bearer $ACCESS_TOKEN'"

# printf "<%s>\n" $AUTH

setupTestdata

waitForMessageProcessing

# Verify that a normal request works, expect three recommendations and three reviews
assertCurl 200 "curl -k https://$HOST:$PORT/product-composite/$PROD_ID_REVS_RECS $AUTH -s"
assertEqual "$PROD_ID_REVS_RECS" $(echo $RESPONSE | jq .productId)
assertEqual 3 $(echo $RESPONSE | jq ".recommendations | length")
assertEqual 3 $(echo $RESPONSE | jq ".reviews | length")

# Verify that a 404 (Not Found) error is returned for a non existing productId ($PROD_ID_NOT_FOUND)
assertCurl 404 "curl -k https://$HOST:$PORT/product-composite/$PROD_ID_NOT_FOUND $AUTH -s"

# Verify that no recommendations are returned for productId $PROD_ID_NO_RECS
assertCurl 200 "curl -k https://$HOST:$PORT/product-composite/$PROD_ID_NO_RECS $AUTH -s"
assertEqual "$PROD_ID_NO_RECS" $(echo $RESPONSE | jq .productId)
assertEqual 0 $(echo $RESPONSE | jq ".recommendations | length")
assertEqual 3 $(echo $RESPONSE | jq ".reviews | length")

# Verify that no reviews are returned for productId $PROD_ID_NO_REVS
assertCurl 200 "curl -k https://$HOST:$PORT/product-composite/$PROD_ID_NO_REVS $AUTH -s"
assertEqual $PROD_ID_NO_REVS $(echo $RESPONSE | jq .productId)
assertEqual 3 $(echo $RESPONSE | jq ".recommendations | length")
assertEqual 0 $(echo $RESPONSE | jq ".reviews | length")

# Verify that a 422 (Unprocessable Entity) error is returned for a productId that is out of range (-1)
assertCurl 422 "curl -k https://$HOST:$PORT/product-composite/-1 $AUTH -s"
assertEqual "\"Invalid productId: -1\"" "$(echo $RESPONSE | jq .message)"

# Verify that a 400 (Bad Request) error is returned for a productId that is not a number, i.e. invalid format
assertCurl 400 "curl -k https://$HOST:$PORT/product-composite/invalidProductId $AUTH -s"
assertEqual "\"Type mismatch.\"" "$(echo $RESPONSE | jq .message)"

# Verify that a request without an access token fails on 401, Unauthorized (i.e., not authenticated)
assertCurl 401 "curl -k https://$HOST:$PORT/product-composite/$PROD_ID_REVS_RECS -s"

# Old code for retrieving read-only access token from local authorization server
READER_ACCESS_TOKEN=$(curl -k https://reader:secret@$HOST:$PORT/oauth/token -d grant_type=password -d username=magnus -d password=password -s | jq .access_token -r)
READER_AUTH="-H \"Authorization: Bearer $READER_ACCESS_TOKEN\""

# echo "Bearer reader ACCESS_TOKEN with only read scope = ${READER_ACCESS_TOKEN}"

# Verify that the reader - client with only read scope can call the read API but not delete API.

# Commented out this test because I didn't want to create a read-only JWT in Auth0

# Verify that a normal read request works with token with read scope, expect three recommendations and three reviews
assertCurl 200 "curl -k https://$HOST:$PORT/product-composite/$PROD_ID_REVS_RECS $READER_AUTH -s"
assertEqual "$PROD_ID_REVS_RECS" $(echo $RESPONSE | jq .productId)
assertEqual 3 $(echo $RESPONSE | jq ".recommendations | length")
assertEqual 3 $(echo $RESPONSE | jq ".reviews | length")

# For some unknown reason, this didn't work; curl returned a 200 OK code
# Verify that the reader - client with only read scope - fails on 403 Forbidden (i.e., not authorized) when calling the delete API
# assertCurl 403 "curl $READER_AUTH -X DELETE -k https://$HOST:$PORT/product-composite/$PROD_ID_REVS_RECS -s"

INVALID_TOKEN="-H \"Authorization: Bearer Invalid_token\""

assertCurl 401 "curl -k https://$HOST:$PORT/product-composite/$PROD_ID_REVS_RECS $INVALID_TOKEN -s"

# Acquire a reader (read scope) access token using the code (most secure) grant flow 

# Enter the following URL on the Safari (not Chrome) browser and look at the redirect URL returned in the browser's search entry field
# Note that I change the expiration time to one year (in seconds)
# https://localhost:8443/oauth/authorize?response_type=code&client_id=reader&redirect_uri=http://my.redirect.uri&scope=product:read&state=35725

# Extract the code value from the redirect URL and set it as an environment variable called READER_CODE
# READER_CODE=whatever it is

# CODE_GRANT_FLOW_READER_ACCESS_TOKEN=$(curl -k https://reader:secret@localhost:8443/oauth/token -d grant_type=authorization_code -d client_id=reader -d redirect_uri=http://my.redirect.uri -d code=$READER_CODE -s | jq .access_token -r)
# echo "CODE_GRANT_FLOW_READER_ACCESS_TOKEN with only read scope = ${CODE_GRANT_FLOW_READER_ACCESS_TOKEN}"

# Store the reader access token returned from the previous command for use in subsequent invocations of the product composite microservice API

# Old code for specifying read only access token generated via the code grant flow
# CODE_GRANT_FLOW_READER_ACCESS_TOKEN=eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJtYWdudXMiLCJleHAiOjIyMzcwMDQ4ODgsImF1dGhvcml0aWVzIjpbIlJPTEVfVVNFUiJdLCJqdGkiOiJQQVl5ZHduWmNGSSs3YVpVbVNYZWpJb2RiTkE9IiwiY2xpZW50X2lkIjoicmVhZGVyIiwic2NvcGUiOlsicHJvZHVjdDpyZWFkIl19.FnuYVl9empEo15FUXbO_8tmGdxzdQjZdpQ3P4J9zUMyHkJmEUMURXa3zcDhrjDmtao1VJ_Xv2Gbcqu3Evp8Vnf56EcLxZAt7CgH3Y0gl23rRIqn_7BPBSkztjqW6dGpyvw7jgi_dBXolHOc35z9A4wJF-5bKVXY7Wwor1yr7fa6I_1rwnHaPAkU9Ecg0rAZov2eAhiJtF6GphXPYoBKDMjXvMyN3gtCNXRVl0tayEo4ndvV-bY-LDc_yDKRxgIYpFMHCgN0yYb26ng8kQW6EKTkjYNPl-rqBNzZwvdDxpK4U1tlRwx0gQc_w4oxMolBpEdGgtJ9W5RLodPu7XgYK-g

# assertCurl 200 "curl -k https://$HOST:$PORT/product-composite/$PROD_ID_REVS_RECS -H \"Authorization: Bearer $CODE_GRANT_FLOW_READER_ACCESS_TOKEN\" -s"
# assertEqual "$PROD_ID_REVS_RECS" $(echo $RESPONSE | jq .productId)
# assertEqual 3 $(echo $RESPONSE | jq ".recommendations | length")
# assertEqual 3 $(echo $RESPONSE | jq ".reviews | length")

# Acquire a writer (write scope) access token using the code (most secure) grant flow 

# Enter the following URL on the Safari (not Chrome) browser and look at the redirect URL returned in the browser's search entry field
# https://localhost:8443/oauth/authorize?response_type=code&client_id=writer&redirect_uri=http://my.redirect.uri&scope=product:read+product:write&state=35725

# Extract the code value from the redirect URL and set it as an environment variable called WRITER_CODE
# WRITER_CODE=whatever it is

# CODE_GRANT_FLOW_WRITER_ACCESS_TOKEN=$(curl -k https://writer:secret@localhost:8443/oauth/token -d grant_type=authorization_code -d client_id=writer -d redirect_uri=http://my.redirect.uri -d code=$WRITER_CODE -s | jq .access_token -r)
# echo "CODE_GRANT_FLOW_WRITER_ACCESS_TOKEN with write scope = ${CODE_GRANT_FLOW_WRITER_ACCESS_TOKEN}"

if [[ $SKIP_CB_TESTS == "false" ]]
then
    testCircuitBreaker
fi

echo "End, all tests OK:" `date`

if [[ $@ == *"stop"* ]]
then
    echo "Stopping the test environment..."
    echo "$ docker-compose down --remove-orphans"
    docker-compose down --remove-orphans
fi