#!/usr/bin/env bash

: ${HOST=localhost}
# : ${PORT=8080}
: ${PORT=8443}
: ${PROD_ID_REVS_RECS=2}

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
    if $url -ks -f -o /dev/null
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

    echo
}

function testCompositeCreated() {

    # Expect that the Product Composite for productId $PROD_ID_REVS_RECS has been created with three recommendations and three reviews
    if ! assertCurl 200 "curl http://$HOST:$PORT/product-composite/$PROD_ID_REVS_RECS -s"
    then
        echo -n "FAIL"
        return 1
    fi
}

function recreateComposite() {
    local productId=$1
    local composite=$2

    # assertCurl 200 "curl -X DELETE https://$HOST:$PORT/product-composite/${productId} -s"
    # curl -X POST http://$HOST:$PORT/product-composite -H "Content-Type: application/json" --data "$composite"

    assertCurl 202 "curl -X DELETE $AUTH -k https://$HOST:$PORT/product-composite/${productId} -s"
    assertEqual 202 $(curl -X POST -s -k https://$HOST:$PORT/product-composite -H "Content-Type: application/json" -H "Authorization: Bearer $ACCESS_TOKEN" --data "$composite" -w "%{http_code}")

}

function setupTestdata() {

  echo "Writing the test data ..."

  n=2
  until [ $n == 100 ] 
    do

      echo "Creating entry for product ID = $n..."

      body="{\"productId\":$n"
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
      recreateComposite $n "$body"

      n=$((n + 1))

    done

}

function readAndValidateTestData() {

  echo "Reading and validating the test data ..."

  # Verify that a normal request works, expect three recommendations and three reviews

  n=2
  until [ $n == 100 ] 
    do

      echo "Reading and validating entry for product ID = $n..."

      assertCurl 200 "curl $AUTH -k https://$HOST:$PORT/product-composite/$n -s"

      assertEqual "$n" $(echo $RESPONSE | jq .productId)
      assertEqual 3 $(echo $RESPONSE | jq ".recommendations | length")
      assertEqual 3 $(echo $RESPONSE | jq ".reviews | length")

      n=$((n + 1))

    done
}


set -e

echo "Start generating traffic....." $(date)

echo "HOST=${HOST}"
echo "PORT=${PORT}"

waitForService curl -k https://$HOST:$PORT/actuator/health

ACCESS_TOKEN=$(curl -k https://writer:secret@$HOST:$PORT/oauth2/token -d grant_type=client_credentials -s | jq .access_token -r)
echo ACCESS_TOKEN=$ACCESS_TOKEN
AUTH="-H \"Authorization: Bearer $ACCESS_TOKEN\""

setupTestdata

readAndValidateTestData

echo "End, all tests OK:" $(date)

if [[ $@ == *"stop"* ]]
then
    echo "Stopping the test environment..."
    echo "$ docker-compose down --remove-orphans"
    docker-compose down --remove-orphans
fi