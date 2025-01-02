import os
from datetime import datetime, timedelta, timezone
from typing import Union

from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.responses import JSONResponse, Response
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from jose import JWTError, jwt
from passlib.context import CryptContext
from pydantic import BaseModel

from dkd.fastapi_constants import DKD_BASE_URL

# Generate a random secret key with the following command: openssl rand -hex 32
JWT_SECRET_KEY = os.environ.get(
    "JWT_SECRET_KEY", "edd19e500549fff0be54380691528541dc0df7142b62be4ac033504d97e871a7"
)
DEFAULT_AUTH_USER_PASSWORD = os.environ.get(
    "DEFAULT_AUTH_USER_PASSWORD",
    "$2b$12$tKgIi5lY4.Ddz0GGqpvzDez73z7s7JgOirhl3XBeIht892Onr4Ay6",  # get_password_hash('password')
)
DEFAULT_AUTH_USER = os.environ.get(
    "DEFAULT_AUTH_USER",
    "dkd",
)
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30


fake_users_db = {
    "dkd": {
        "username": "dkd",
        "full_name": "Dynamic Kube Deploy",
        "email": "dkd@noreply.com",
        "hashed_password": DEFAULT_AUTH_USER_PASSWORD,
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
        expire = datetime.now(timezone.utc) + expires_delta
    else:
        expire = datetime.now(timezone.utc) + timedelta(minutes=15)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, JWT_SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt


async def get_current_auth_user(token: str = Depends(oauth2_scheme)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials, it might need to be refreshed",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, JWT_SECRET_KEY, algorithms=[ALGORITHM])
        username: str = payload.get("sub", "")
        if not username:
            raise credentials_exception
        token_data = TokenData(username=username)
    except JWTError:
        raise credentials_exception
    user = get_user(fake_users_db, username=token_data.username or "")
    if user is None:
        raise credentials_exception
    return user


async def get_current_active_user(current_user: User = Depends(get_current_auth_user)):
    if current_user.disabled:
        raise HTTPException(status_code=400, detail="Inactive user")
    return current_user


async def login_for_access_token(
    form_data: OAuth2PasswordRequestForm = Depends(),
) -> Response:
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
    return JSONResponse(content={"access_token": access_token, "token_type": "bearer"})


async def get_current_user(
    current_user: User = Depends(get_current_auth_user),
) -> User:
    return current_user


def secureApp(app: FastAPI):
    app.add_api_route(
        f"{DKD_BASE_URL}/token",
        login_for_access_token,
        methods=["POST"],
        response_model=Token,
        tags=["Authentication"],
    )
    app.add_api_route(
        f"{DKD_BASE_URL}/token_info",
        get_current_user,
        methods=["GET"],
        response_model=User,
        tags=["Authentication"],
    )


if __name__ == "__main__":
    print(get_password_hash("password"))
