"""
This module provides logging functionalities for FastAPI applications.
It includes a custom log function and a custom API route class that logs incoming requests.

Classes:
  LogRoute(APIRoute): A custom FastAPI route class that logs requests.

Functions:
  log(msg: str, obj: any): Logs a message and an object with pretty print formatting.
"""

from logging import getLogger
from pprint import PrettyPrinter
from typing import Callable

from fastapi import Request, Response
from fastapi.routing import APIRoute

from dkd.fastapi_constants import LOG_REQUEST

logger = getLogger("uvicorn.info")
pp = PrettyPrinter(indent=2)


def log(msg: str, obj: any) -> None:
    """
    Logs the given message and object.

    Args:
      msg (str): The message to be logged.
      obj (any): The object to be logged.
    """
    logger.info("%s:\n%s", msg, pp.pformat(obj))


class LogRoute(APIRoute):
    """
    A custom FastAPI route class that logs incoming requests.

    This class overrides the default route handler to log request details before passing the request to the original handler.
    It is useful for debugging and monitoring purposes.

    Attributes:
      None

    Methods:
      get_route_handler(): Overrides the default method to return a custom route handler that logs requests.
    """

    def get_route_handler(self) -> Callable:
        """
        Returns the custom route handler for the LogRoute.

        Returns:
          Callable: The custom route handler.
        """
        original_route_handler = super().get_route_handler()

        async def custom_route_handler(request: Request) -> Response:
            """
            Custom route handler that logs the request headers and body.

            Args:
              request (Request): The incoming request.

            Returns:
              Response: The response from the original route handler.
            """
            if LOG_REQUEST:
                log("Headers", request.headers.items())
                logger.info("Body:\n%s", (await request.body()).decode("utf-8"))
            return await original_route_handler(request)

        return custom_route_handler
