# Nginx

```shell
# To restart nginx from within the container
nginx-debug -s reload
nginx -s reload

# To restart nginx
docker exec -ti nginx nginx-debug -s reload
docker exec -ti nginx nginx -s reload
```
