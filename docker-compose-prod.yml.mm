version: "2.1"

services:
  product:
    build: microservices/product-service
    image: hands-on/product-service
    mem_limit: 350m
    networks:
      - my-network
    environment:
      - SPRING_PROFILES_ACTIVE=docker
      - CONFIG_SERVER_USR=${CONFIG_SERVER_USR}
      - CONFIG_SERVER_PWD=${CONFIG_SERVER_PWD}
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
      - SPRING_PROFILES_ACTIVE=docker
      - CONFIG_SERVER_USR=${CONFIG_SERVER_USR}
      - CONFIG_SERVER_PWD=${CONFIG_SERVER_PWD}
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
      - SPRING_PROFILES_ACTIVE=docker
      - CONFIG_SERVER_USR=${CONFIG_SERVER_USR}
      - CONFIG_SERVER_PWD=${CONFIG_SERVER_PWD}
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
    environment:
      - SPRING_PROFILES_ACTIVE=docker
      - CONFIG_SERVER_USR=${CONFIG_SERVER_USR}
      - CONFIG_SERVER_PWD=${CONFIG_SERVER_PWD}
    depends_on:
      rabbitmq:
        condition: service_healthy

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
