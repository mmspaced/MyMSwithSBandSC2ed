version: '2.1'

services:

  mysql:
    image: arm64v8/mysql:8.0.29-oracle
    mem_limit: 512m
    ports:
      - "3306:3306"
    environment:
      # - MYSQL_ROOT_PASSWORD=rootpwd
      - MYSQL_ROOT_PASSWORD=rootpwd1
      - MYSQL_DATABASE=review-db
      - MYSQL_USER=user
      - MYSQL_PASSWORD=pwd
    healthcheck:
      test: "/usr/bin/mysql --user=user --password=pwd --execute \"SHOW DATABASES;\""
      interval: 5s
      timeout: 2s
      retries: 60