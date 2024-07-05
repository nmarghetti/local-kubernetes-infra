#! /usr/bin/env python


# --------------------------------------------------------- API ENV SECTION
import os

LOG_REQUEST = os.environ.get("LOG_REQUEST", "false").lower() == "true"

ALLOW_UNAUTHENTICATED = (
    os.environ.get("ALLOW_UNAUTHENTICATED", "false").lower() == "true"
)

ANONYMOUS_TOKEN = os.environ.get("ANONYMOUS_TOKEN", "0IUUSwyB3xOsJxr4i1ixgdrZr4QjJK")

DKD_BASE_URL = os.environ.get("DKD_BASE_URL", "/dkd")

# --------------------------------------------------------- API SECURITY SECTION
from datetime import datetime, timedelta, timezone
from typing import Union

from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from jose import JWTError, jwt
from passlib.context import CryptContext
from pydantic import BaseModel

# to get a string like this run:
# openssl rand -hex 32
SECRET_KEY = "a7e6a0e8c2f7916b0efebedf7ce892a8f1e8eefcb8f9e2bc32b652fecb91cdd4"
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30

fake_users_db = {
    "dkd": {
        "username": "dkd",
        "full_name": "Dynamic Kube Deploy",
        "email": "dkd@noreply.com",
        "hashed_password": "$2b$12$jTTgfB7MTo45u8t77iluu.5fWcLLMfXjva0MrlmGhzZrmg9l.dy4O",  # get_password_hash('FzrSlHvtiq1KBoAVDIMmxfdHJLgalvQRiG1Wkums')
        "disabled": False,
    }
}


class Token(BaseModel):
    access_token: str
    token_type: str


class TokenData(BaseModel):
    username: Union[str, None] = None


class User(BaseModel):
    username: str
    email: Union[str, None] = None
    full_name: Union[str, None] = None
    disabled: Union[bool, None] = None


class UserInDB(User):
    hashed_password: str


pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

oauth2_scheme = OAuth2PasswordBearer(tokenUrl=f"{DKD_BASE_URL}/token")

app = FastAPI(
    docs_url=f"{DKD_BASE_URL}/docs",
    redoc_url=f"{DKD_BASE_URL}/redoc",
    openapi_url=f"{DKD_BASE_URL}/openapi.json",
)


def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)


def get_password_hash(password):
    return pwd_context.hash(password)


def get_user(db, username: str):
    if username in db:
        user_dict = db[username]
        return UserInDB(**user_dict)


def authenticate_user(fake_db, username: str, password: str):
    user = get_user(fake_db, username)
    if not user:
        return False
    if not verify_password(password, user.hashed_password):
        return False
    return user


def create_access_token(data: dict, expires_delta: Union[timedelta, None] = None):
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=15)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt


async def get_current_user(token: str = Depends(oauth2_scheme)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials, it might need to be refreshed",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            raise credentials_exception
        token_data = TokenData(username=username)
    except JWTError:
        raise credentials_exception
    user = get_user(fake_users_db, username=token_data.username)
    if user is None:
        raise credentials_exception
    return user


async def get_current_active_user(current_user: User = Depends(get_current_user)):
    if current_user.disabled:
        raise HTTPException(status_code=400, detail="Inactive user")
    return current_user


@app.post(f"{DKD_BASE_URL}/token", response_model=Token)
async def login_for_access_token(form_data: OAuth2PasswordRequestForm = Depends()):
    user = authenticate_user(fake_users_db, form_data.username, form_data.password)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": user.username}, expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer"}


# --------------------------------------------------------- API DEBUG SECTION
from typing import Callable
from fastapi import Request, Response
from fastapi.routing import APIRoute
import logging
from pprint import PrettyPrinter

logger = logging.getLogger("uvicorn.info")
pp = PrettyPrinter(indent=2)


def log(msg: str, obj: any) -> None:
    logger.info("%s:\n%s", msg, pp.pformat(obj))


class LogRoute(APIRoute):
    def get_route_handler(self) -> Callable:
        original_route_handler = super().get_route_handler()

        async def custom_route_handler(request: Request) -> Response:
            if LOG_REQUEST:
                log("Headers", request.headers.items())
                logger.info("Body: %s", await request.body())
            return await original_route_handler(request)

        return custom_route_handler


app.router.route_class = LogRoute

# --------------------------------------------------------- API SECTION
from pydantic import BaseModel
from fastapi import HTTPException
from datetime import datetime, time
import pytz
import json
from unittest.mock import Mock

# from pytz import timezone


class Message(BaseModel):
    events: list[dict]


def shouldAlert() -> bool:
    now = datetime.now(pytz.timezone("Europe/Paris"))
    nowTime = now.time()
    return True


@app.post(f"{DKD_BASE_URL}/info")
async def info(current_user: User = Depends(get_current_user)):
    return "No information today."


@app.get(f"{DKD_BASE_URL}/time")
async def timeSlot():
    return {
        "time": datetime.utcnow().strftime("%c"),
        "nce_time": datetime.now(pytz.timezone("Europe/Paris")).strftime("%c"),
        "should_call": shouldAlert(),
    }


@app.post(f"{DKD_BASE_URL}/anonymous/docker-push")
async def dockerPush(message: Message, request: Request, token=None):
    if not ALLOW_UNAUTHENTICATED:
        raise HTTPException(status_code=401, detail="Unauthorized")
    if token != ANONYMOUS_TOKEN:
        raise HTTPException(status_code=401, detail="Invalid token")
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
                log("Pushing new image", image)


# def main():
#   import uvicorn
#   uvicorn.run(app, port=8100, log_level="info")
#   return

# if __name__ == "__main__":
#     main()
