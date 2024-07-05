# DKD

Using [fastpi](https://fastapi.tiangolo.com/)

```shell
poetry install
DRY_RUN=true ALLOW_UNAUTHENTICATED=true poetry run uvicorn --log-config ./logging.yaml --host 0.0.0.0 --port 8100 --reload dkd.main:app
```

Check to api dock under <http://127.0.0.1:8100/dkd/docs>
