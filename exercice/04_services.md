# Docker compose local services

```shell
REGISTRY_UI_PORT=8087 envsubst '$REGISTRY_UI_PORT' <./docker-compose/docker/registry/config/config.template.yaml >./docker-compose/docker/registry/config/config.yaml
cp ./docker-compose/docker/dnsmasq/dnsmasq.template.conf ./docker-compose/docker/dnsmasq/dnsmasq.conf

docker compose -f ./docker-compose/docker-compose.yaml up -d --build
docker ps
docker logs init-portainer
docker logs init-gitea

# Check docker registry
curl -sS http://localhost:5007/v2/_catalog | jq

# Check helm registry
curl -sS  http://localhost:8088/api/charts | jq
```

Check portainer: <http://localhost:9400/>

Check gitea server: <http://localhost:3000/gitadmin/local_cluster>
