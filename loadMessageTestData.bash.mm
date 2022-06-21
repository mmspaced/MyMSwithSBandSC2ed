#!/usr/bin/env bash
#

# To create composite product test data that we can use to examine how it is processed in RabbitMQ, we use the  following commands:

body='{"productId":1,"name":"product name C","weight":300,"recommendations":[{"recommendationId": 1, "author":"author 1", "rate":1,"content":"content 1"},{"recommendationId":2,"author":"author 2","rate": 2,"content":"content 2"},{"recommendationId":3,"author":"author 3","rate":3,"content":"content 3"}],"reviews":[{"reviewId":1,"author":"author 1","subject":"subject 1","content":"content 1"},{"reviewId":2,"author":"author 2","subject":"subject 2","content":"content 2"},{"reviewId": 3,"author":"author 3","subject":"subject 3","content":"content 3"}]}' 

# And invoke the product-composite API to send the payload using the following curl command:

curl -X POST http://localhost:8080/product-composite -H "Content-Type: application/json" --data "$body"

