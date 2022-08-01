#!/usr/bin/env bash
#

# Use the appropriate docker-compose file for kafka and development environment 
cp docker-compose-kafka.yml docker-compose.yml
echo "Copied docker-compose-kafka.yml to docker-compose.yml for kafka and development"

./gradlew build && docker-compose build

./test-em-all.bash start kafka
