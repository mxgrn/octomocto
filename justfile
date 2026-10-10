remote:
  DOCKER_HOST=ssh://app1 docker exec -ti octomocto_prod /app/bin/octomocto remote

remote_staging:
  DOCKER_HOST=ssh://app1 docker exec -ti octomocto_staging /app/bin/octomocto remote

logs:
  @./bin/logs

logs_staging:
  @./bin/logs_staging
