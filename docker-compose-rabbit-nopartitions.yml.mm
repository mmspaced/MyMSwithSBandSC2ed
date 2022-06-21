version: "2.1"

services:
  product:
    build: microservices/product-service
    image: hands-on/product-service
    mem_limit: 350m
    networks:
      - my-network
    environment:
      # - SPRING_PROFILES_ACTIVE=docker,streaming_partitioned,streaming_instance_0,kafka
      - SPRING_PROFILES_ACTIVE=docker
      - CONFIG_SERVER_USR=${CONFIG_SERVER_USR}
      - CONFIG_SERVER_PWD=${CONFIG_SERVER_PWD}
      # - MANAGEMENT_HEALTH_RABBIT_ENABLED=false
      # - SPRING_CLOUD_STREAM_DEFAULTBINDER=kafka
      # - SPRING_CLOUD_STREAM_BINDINGS_INPUT_CONSUMER_PARTITIONED=true
      # - SPRING_CLOUD_STREAM_BINDINGS_INPUT_CONSUMER_INSTANCECOUNT=2
      # - SPRING_CLOUD_STREAM_BINDINGS_INPUT_CONSUMER_INSTANCEINDEX=0
    depends_on:
      mongodb:
        condition: service_healthy
      rabbitmq:
        condition: service_healthy

  recommendation:
    build: microservices/recommendation-service
    image: hands-on/recommendation-service
    mem_limit: 350m
    networks:
      - my-network
    environment:
      # - SPRING_PROFILES_ACTIVE=docker,streaming_partitioned,streaming_instance_0,kafka
      - SPRING_PROFILES_ACTIVE=docker
      - CONFIG_SERVER_USR=${CONFIG_SERVER_USR}
      - CONFIG_SERVER_PWD=${CONFIG_SERVER_PWD}
      # - MANAGEMENT_HEALTH_RABBIT_ENABLED=false
      # - SPRING_CLOUD_STREAM_DEFAULTBINDER=kafka
      # - SPRING_CLOUD_STREAM_BINDINGS_INPUT_CONSUMER_PARTITIONED=true
      # - SPRING_CLOUD_STREAM_BINDINGS_INPUT_CONSUMER_INSTANCECOUNT=2
      # - SPRING_CLOUD_STREAM_BINDINGS_INPUT_CONSUMER_INSTANCEINDEX=0
    depends_on:
      mongodb:
        condition: service_healthy
      rabbitmq:
        condition: service_healthy

  review:
    build: microservices/review-service
    image: hands-on/review-service
    mem_limit: 350m
    networks:
      - my-network
    environment:
      # - SPRING_PROFILES_ACTIVE=docker,streaming_partitioned,streaming_instance_0,kafka
      - SPRING_PROFILES_ACTIVE=docker
      - CONFIG_SERVER_USR=${CONFIG_SERVER_USR}
      - CONFIG_SERVER_PWD=${CONFIG_SERVER_PWD}
      # - MANAGEMENT_HEALTH_RABBIT_ENABLED=false
      # - SPRING_CLOUD_STREAM_DEFAULTBINDER=kafka
      # - SPRING_CLOUD_STREAM_BINDINGS_INPUT_CONSUMER_PARTITIONED=true
      # - SPRING_CLOUD_STREAM_BINDINGS_INPUT_CONSUMER_INSTANCECOUNT=2
      # - SPRING_CLOUD_STREAM_BINDINGS_INPUT_CONSUMER_INSTANCEINDEX=0
    depends_on:
      mongodb:
        condition: service_healthy
      rabbitmq:
        condition: service_healthy

  product-composite:
    build: microservices/product-composite-service
    image: hands-on/product-composite-service
    mem_limit: 350m
    networks:
      - my-network
    # ports:
    #   - "8080:8080"
    environment:
      # - SPRING_PROFILES_ACTIVE=docker,streaming_partitioned,kafka
      - SPRING_PROFILES_ACTIVE=docker
      - CONFIG_SERVER_USR=${CONFIG_SERVER_USR}
      - CONFIG_SERVER_PWD=${CONFIG_SERVER_PWD}
      # - MANAGEMENT_HEALTH_RABBIT_ENABLED=false
      # - SPRING_CLOUD_STREAM_DEFAULTBINDER=kafka
      # - SPRING_CLOUD_STREAM_BINDINGS_OUTPUT-PRODUCTS_PRODUCER_PARTITION-KEY-EXPRESSION=payload.key
      # - SPRING_CLOUD_STREAM_BINDINGS_OUTPUT-PRODUCTS_PRODUCER_PARTITION-COUNT=2
      # - SPRING_CLOUD_STREAM_BINDINGS_OUTPUT-RECOMMENDATIONS_PRODUCER_PARTITION-KEY-EXPRESSION=payload.key
      # - SPRING_CLOUD_STREAM_BINDINGS_OUTPUT-RECOMMENDATIONS_PRODUCER_PARTITION-COUNT=2
      # - SPRING_CLOUD_STREAM_BINDINGS_OUTPUT-REVIEWS_PRODUCER_PARTITION-KEY-EXPRESSION=payload.key
      # - SPRING_CLOUD_STREAM_BINDINGS_OUTPUT-REVIEWS_PRODUCER_PARTITION-COUNT=2
    depends_on:
      rabbitmq:
        condition: service_healthy

  mongodb:
    image: mongo:3.6.9
    mem_limit: 350m
    networks:
      - my-network
    ports:
      - "27017:27017"
    command: mongod --smallfiles
    healthcheck:
      test: "mongo --eval 'db.stats().ok'"
      interval: 20s
      timeout: 5s
      retries: 10

  # $ mysql -uroot -h127.0.0.1 -p
  mysql:
    image: mysql:5.7
    mem_limit: 350m
    networks:
      - my-network
    ports:
      - "3306:3306"
    environment:
      - MYSQL_ROOT_PASSWORD=rootpwd1
      - MYSQL_DATABASE=review-db
      - MYSQL_USER=user
      - MYSQL_PASSWORD=pwd
    healthcheck:
      test: '/usr/bin/mysql --user=user --password=pwd --execute "SHOW DATABASES;"'
      interval: 20s
      timeout: 5s
      retries: 10

  rabbitmq:
    image: rabbitmq:3.7.8-management
    mem_limit: 350m
    networks:
      - my-network
    ports:
      - 5672:5672
      - 15672:15672
    healthcheck:
      test: [ "CMD", "rabbitmqctl", "status" ]
      interval: 20s
      timeout: 5s
      retries: 10

  gateway:
    build: gateway-server
    image: hands-on/gateway
    mem_limit: 350m
    networks:
      - my-network
    ports:
      - "8443:8443"
    environment:
      - SPRING_PROFILES_ACTIVE=docker
      - CONFIG_SERVER_USR=${CONFIG_SERVER_USR}
      - CONFIG_SERVER_PWD=${CONFIG_SERVER_PWD}

  auth-server:
    build: authorization-server
    image: hands-on/auth-server
    mem_limit: 350m
    networks:
      - my-network
    environment:
      - SPRING_PROFILES_ACTIVE=docker
      - CONFIG_SERVER_USR=${CONFIG_SERVER_USR}
      - CONFIG_SERVER_PWD=${CONFIG_SERVER_PWD}

  config-server:
    build: config-server
    image: hands-on/config-server
    mem_limit: 350m
    networks:
      - my-network
    environment:
      - SPRING_PROFILES_ACTIVE=docker, native
      - ENCRYPT_KEY=${CONFIG_SERVER_ENCRYPT_KEY}
      - SPRING_SECURITY_USER_NAME=${CONFIG_SERVER_USR}
      - SPRING_SECURITY_USER_PASSWORD=${CONFIG_SERVER_PWD}
    volumes:
      - $PWD/config-repo:/config-repo

  # zipkin:
  #   image: openzipkin/zipkin:2.12.9
  #   mem_limit: 512m
  #   networks:
  #     - my-network
  #   environment:
  #     - STORAGE_TYPE=mem
  #     - RABBIT_ADDRESSES=rabbitmq
  #   ports:
  #     - 9411:9411
  #   depends_on:
  #     rabbitmq:
  #       condition: service_healthy

networks:
  my-network:
    name: my-network
