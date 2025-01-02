# DKD

Using [fastpi](https://fastapi.tiangolo.com/)

Initialize dkd:

```shell
./scripts/init_dkd.sh
```

Run dkd:

```shell
# Either activate with poetry shell and run it
poetry -C ./dkd shell
dkd --help
# deactive when done
deactivate

# Either run it through poetry
poetry -C ./dkd run dkd --help

# Either run it with uvicorn
DRY_RUN=true ALLOW_UNAUTHENTICATED=true poetry -C ./dkd run uvicorn --log-config ./logging.yaml --host 0.0.0.0 --port 8100 --reload dkd.main:app
```

Check to api dock under <http://127.0.0.1:8100/dkd/docs>
