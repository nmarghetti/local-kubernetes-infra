FROM python:3.13

COPY . /app/

RUN python3 -m pip install --upgrade pip \
  && python3 -m pip install pipx \
  && pipx install poetry==1.8.4

WORKDIR /app

RUN cd /app \
  && /root/.local/bin/poetry install

ENTRYPOINT [ "/root/.local/bin/poetry", "run", "uvicorn", "--log-config", "./logging.yaml", "--host", "0.0.0.0", "--port", "8100", "--reload", "dkd.main:app"]
