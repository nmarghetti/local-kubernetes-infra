#! /usr/bin/env python

import traceback
from contextlib import asynccontextmanager

import uvicorn
from fastapi import Depends, FastAPI, HTTPException, Request
from pydantic import BaseModel
from datetime import datetime, timezone
import pytz

from dkd.fastapi_constants import (
    HOST,
    PORT,
    ALLOW_UNAUTHENTICATED,
    ANONYMOUS_TOKEN,
    DKD_BASE_URL,
    DRY_RUN,
)
from dkd.fastapi_log import LogRoute, logger
from dkd.fastapi_security import User, get_current_active_user, secureApp


@asynccontextmanager
async def lifespan(app: FastAPI):
    # On startup
    if DRY_RUN:
        logger.warning("Service is running in dry mode.")
    logger.info("Service is starting up at %s", DKD_BASE_URL)
    yield
    # On shutdown
    logger.info("Service is shuting down")


app = FastAPI(
    lifespan=lifespan,
    docs_url=f"{DKD_BASE_URL}/docs",
    redoc_url=f"{DKD_BASE_URL}/redoc",
    openapi_url=f"{DKD_BASE_URL}/openapi.json",
)
app.router.route_class = LogRoute
secureApp(app)


def handleException(message: str):
    logger.error(message)
    raise HTTPException(status_code=500, detail=message)


class StatusResponse(BaseModel):
    status: str


class Message(BaseModel):
    events: list[dict]


@app.get(f"{DKD_BASE_URL}/time", tags=["Information"])
async def timeSlot():
    return {
        "time": datetime.now(timezone.utc).strftime("%c"),
        "nce_time": datetime.now(pytz.timezone("Europe/Paris")).strftime("%c"),
    }


@app.post(f"{DKD_BASE_URL}/notify-docker-push", tags=["Images"])
async def dockerPush(message: Message, request: Request, token=None) -> StatusResponse:
    if not ALLOW_UNAUTHENTICATED:
        raise HTTPException(status_code=401, detail="Unauthorized")
    if token != ANONYMOUS_TOKEN:
        raise HTTPException(status_code=401, detail="Invalid token")
    try:
        # print(request.headers)
        # print(request.query_params)
        data = await request.json()
        # print(json.dumps(data))
        # log('Data received', data)
        for event in data.get("events", []):
            if event.get("action", None) == "push":
                target = event.get("target", {})
                repo = target.get("repository", None)
                tag = target.get("tag", None)
                if repo is not None and tag is not None:
                    image = f"{repo}:{tag}"
                    logger.info("Pushing new image: %s", image)
        return StatusResponse(status="ok")
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail="Unable to handle images") from e


def main() -> None:
    uvicorn.run("dkd.main:app", host=HOST, port=PORT, reload=True)


if __name__ == "__main__":
    main()
