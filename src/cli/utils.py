"""CLI utility functions and decorators."""

import asyncio
from functools import wraps
import click


def coro(f):
    """
    A decorator that runs an async function in an event loop.
    This simplifies writing async Click commands.
    """
    @wraps(f)
    def wrapper(*args, **kwargs):
        # The last argument is the Click context
        ctx = args[-1]
        try:
            asyncio.run(f(*args, **kwargs))
        except Exception as e:
            # Get the logger from the context if available
            logger = ctx.obj.logger if hasattr(ctx.obj, 'logger') else click.get_logger()
            logger.error(f"Command failed with error: {e}", exc_info=True)
            click.secho(f"Error: {e}", fg="red")

    return wrapper
