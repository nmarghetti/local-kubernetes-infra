# Docker

## Checking docker

```shell
docker --help
docker ps
docker container ls
docker image ls
docker volume ls
```

## Running a service with docker

```shell
docker run --rm -p 9090:9000 -v '/var/run/docker.sock:/var/run/docker.sock' portainer/portainer-ce:latest
```

- visit <http://localhost:9090/>
- create admin user
- create environment using `Get Started`
- select the `local` environment created
- browse container, images, etc.

```shell
# Create a volume to save data
docker volume create portainer_data
docker run --name portainer_container -d -p 9090:9000 -v '/var/run/docker.sock:/var/run/docker.sock' -v portainer_data:/data portainer/portainer-ce:latest
# You can stop and start again the container, you would have the data saved
```

```shell
# clean up
docker container stop portainer_container
docker container rm portainer_container
docker volume rm portainer_data
```

## Running services with docker compose

Create `services.yaml` with the following content:

```yaml
name: my_services
services:
  portainer:
    container_name: my_portainer
    image: portainer/portainer-ce:latest
    command: --http-enabled
    ports:
      - 9091:9000
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
  podinfo:
    container_name: podinfo
    image: stefanprodan/podinfo
    ports:
      - 9092:9898
    command: ./podinfo --host=0.0.0.0
    environment:
      - PODINFO_UI_MESSAGE=Hello from Docker Compose ($PWD). Check swagger at /swagger/index.html
volumes:
  portainer_data:
```

```shell
docker compose -f ./services.yaml up -d

# Check podinfo container
docker exec -ti podinfo sh -c 'env | sort | grep PODINFO'
docker exec -ti podinfo sh
docker exec -u root -ti podinfo sh
```

Visit <http://localhost:9091/>, <http://localhost:9092/>.

```shell
# clean up
docker compose -f ./services.yaml stop
docker compose -f ./services.yaml rm -f
docker volume rm my_services_portainer_data
```
