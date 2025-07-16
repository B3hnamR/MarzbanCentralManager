"""Logging configuration for Marzban Central Manager."""

import logging
import sys
from pathlib import Path
from typing import Optional
from datetime import datetime


class ColoredFormatter(logging.Formatter):
    """Colored log formatter for console output."""
    
    # ANSI color codes
    COLORS = {
        'DEBUG': '\033[36m',      # Cyan
        'INFO': '\033[32m',       # Green
        'WARNING': '\033[33m',    # Yellow
        'ERROR': '\033[31m',      # Red
        'CRITICAL': '\033[35m',   # Magenta
        'RESET': '\033[0m'        # Reset
    }
    
    def format(self, record):
        # Add color to levelname
        if record.levelname in self.COLORS:
            record.levelname = f"{self.COLORS[record.levelname]}{record.levelname}{self.COLORS['RESET']}"
        
        return super().format(record)


class MarzbanLogger:
    """Logger manager for Marzban Central Manager."""
    
    def __init__(self, name: str = "marzban_manager"):
        self.name = name
        self.logger = logging.getLogger(name)
        self._configured = False
    
    def configure(self, level: str = "INFO", log_file: Optional[str] = None, debug: bool = False):
        """Configure the logger."""
        if self._configured:
            return
        
        # Set level
        log_level = getattr(logging, level.upper(), logging.INFO)
        self.logger.setLevel(log_level)
        
        # Clear existing handlers
        self.logger.handlers.clear()
        
        # Console handler with colors
        console_handler = logging.StreamHandler(sys.stdout)
        console_formatter = ColoredFormatter(
            '%(asctime)s | %(levelname)s | %(message)s',
            datefmt='%H:%M:%S'
        )
        console_handler.setFormatter(console_formatter)
        self.logger.addHandler(console_handler)
        
        # File handler if specified
        if log_file:
            # Ensure log directory exists
            log_path = Path(log_file)
            log_path.parent.mkdir(parents=True, exist_ok=True)
            
            file_handler = logging.FileHandler(log_file, encoding='utf-8')
            file_formatter = logging.Formatter(
                '%(asctime)s | %(levelname)s | %(name)s | %(message)s',
                datefmt='%Y-%m-%d %H:%M:%S'
            )
            file_handler.setFormatter(file_formatter)
            self.logger.addHandler(file_handler)
        
        # Set debug mode
        if debug:
            self.logger.setLevel(logging.DEBUG)
        
        self._configured = True
    
    def debug(self, message: str, **kwargs):
        """Log debug message."""
        self.logger.debug(message, **kwargs)
    
    def info(self, message: str, **kwargs):
        """Log info message."""
        self.logger.info(message, **kwargs)
    
    def warning(self, message: str, **kwargs):
        """Log warning message."""
        self.logger.warning(message, **kwargs)
    
    def error(self, message: str, **kwargs):
        """Log error message."""
        self.logger.error(message, **kwargs)
    
    def critical(self, message: str, **kwargs):
        """Log critical message."""
        self.logger.critical(message, **kwargs)
    
    def success(self, message: str, **kwargs):
        """Log success message (as info with special formatting)."""
        self.logger.info(f"✅ {message}", **kwargs)
    
    def step(self, message: str, **kwargs):
        """Log step message (as info with special formatting)."""
        self.logger.info(f"🔄 {message}", **kwargs)
    
    def prompt(self, message: str, **kwargs):
        """Log prompt message (as info with special formatting)."""
        self.logger.info(f"❓ {message}", **kwargs)


# Global logger instance
logger = MarzbanLogger()


def get_logger(name: str = None) -> MarzbanLogger:
    """Get logger instance."""
    if name:
        return MarzbanLogger(name)
    return logger