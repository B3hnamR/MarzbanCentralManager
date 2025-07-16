"""Async utilities for safe task management."""

import asyncio
import functools
from typing import Callable, Any, Optional, Coroutine
from .logger import get_logger

logger = get_logger("async_utils")


def safe_create_task(coro: Coroutine, name: str = None) -> Optional[asyncio.Task]:
    """
    Safely create an asyncio task only if event loop is running.
    
    Args:
        coro: Coroutine to run
        name: Optional task name for debugging
        
    Returns:
        Task if created successfully, None otherwise
    """
    try:
        loop = asyncio.get_running_loop()
        task = loop.create_task(coro, name=name)
        logger.debug(f"Created task: {name or 'unnamed'}")
        return task
    except RuntimeError:
        logger.debug(f"No event loop running, cannot create task: {name or 'unnamed'}")
        return None


def ensure_event_loop(func: Callable) -> Callable:
    """
    Decorator to ensure function runs in an event loop.
    If no loop is running, creates a new one.
    """
    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        try:
            # Try to get running loop
            loop = asyncio.get_running_loop()
            # If we're already in a loop, just call the function
            return func(*args, **kwargs)
        except RuntimeError:
            # No loop running, create one
            if asyncio.iscoroutinefunction(func):
                return asyncio.run(func(*args, **kwargs))
            else:
                return func(*args, **kwargs)
    
    return wrapper


def run_async_safe(coro: Coroutine) -> Any:
    """
    Safely run a coroutine, handling both cases where event loop
    is running or not.
    """
    try:
        # Try to get running loop
        loop = asyncio.get_running_loop()
        # If loop is running, create task
        task = loop.create_task(coro)
        return task
    except RuntimeError:
        # No loop running, run directly
        return asyncio.run(coro)


class SafeTaskManager:
    """Manager for safely handling async tasks."""
    
    def __init__(self):
        self.tasks = set()
        self.logger = get_logger("task_manager")
    
    def create_task(self, coro: Coroutine, name: str = None) -> Optional[asyncio.Task]:
        """Create and track a task safely."""
        task = safe_create_task(coro, name)
        if task:
            self.tasks.add(task)
            task.add_done_callback(self.tasks.discard)
        return task
    
    async def cancel_all(self):
        """Cancel all tracked tasks."""
        if not self.tasks:
            return
        
        self.logger.info(f"Cancelling {len(self.tasks)} tasks")
        
        for task in self.tasks.copy():
            task.cancel()
        
        # Wait for all tasks to complete
        await asyncio.gather(*self.tasks, return_exceptions=True)
        self.tasks.clear()
    
    def __len__(self):
        return len(self.tasks)


# Global task manager
task_manager = SafeTaskManager()