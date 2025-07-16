"""Configuration management for Marzban Central Manager."""

import os
import yaml
from pathlib import Path
from typing import Optional, Dict, Any
from dataclasses import dataclass


@dataclass
class MarzbanConfig:
    """Marzban panel configuration."""
    base_url: str
    username: str
    password: str
    timeout: int = 30
    verify_ssl: bool = True


@dataclass
class AppConfig:
    """Application configuration."""
    debug: bool = False
    log_level: str = "INFO"
    log_file: Optional[str] = None
    
    # Marzban panel settings
    marzban: Optional[MarzbanConfig] = None
    
    # Telegram settings (for future use)
    telegram_bot_token: Optional[str] = None
    telegram_chat_id: Optional[str] = None
    
    # Monitoring settings
    health_check_interval: int = 300  # 5 minutes
    retry_attempts: int = 3
    retry_delay: int = 2


class ConfigManager:
    """Manages application configuration."""
    
    def __init__(self, config_path: Optional[str] = None):
        self.config_path = config_path or self._get_default_config_path()
        self._config: Optional[AppConfig] = None
    
    def _get_default_config_path(self) -> str:
        """Get default configuration file path."""
        return os.path.join(Path(__file__).parent.parent.parent, "config", "settings.yaml")
    
    def load_config(self) -> AppConfig:
        """Load configuration from file."""
        if self._config is not None:
            return self._config
        
        if not os.path.exists(self.config_path):
            self._create_default_config()
        
        with open(self.config_path, 'r', encoding='utf-8') as f:
            data = yaml.safe_load(f) or {}
        
        # Parse Marzban config
        marzban_data = data.get('marzban', {})
        marzban_config = None
        if marzban_data.get('base_url') and marzban_data.get('username'):
            marzban_config = MarzbanConfig(
                base_url=marzban_data['base_url'],
                username=marzban_data['username'],
                password=marzban_data['password'],
                timeout=marzban_data.get('timeout', 30),
                verify_ssl=marzban_data.get('verify_ssl', True)
            )
        
        self._config = AppConfig(
            debug=data.get('debug', False),
            log_level=data.get('log_level', 'INFO'),
            log_file=data.get('log_file'),
            marzban=marzban_config,
            telegram_bot_token=data.get('telegram', {}).get('bot_token'),
            telegram_chat_id=data.get('telegram', {}).get('chat_id'),
            health_check_interval=data.get('monitoring', {}).get('health_check_interval', 300),
            retry_attempts=data.get('api', {}).get('retry_attempts', 3),
            retry_delay=data.get('api', {}).get('retry_delay', 2)
        )
        
        return self._config
    
    def save_config(self, config: AppConfig) -> None:
        """Save configuration to file."""
        data = {
            'debug': config.debug,
            'log_level': config.log_level,
            'log_file': config.log_file,
            'marzban': {
                'base_url': config.marzban.base_url if config.marzban else '',
                'username': config.marzban.username if config.marzban else '',
                'password': config.marzban.password if config.marzban else '',
                'timeout': config.marzban.timeout if config.marzban else 30,
                'verify_ssl': config.marzban.verify_ssl if config.marzban else True
            } if config.marzban else {},
            'telegram': {
                'bot_token': config.telegram_bot_token,
                'chat_id': config.telegram_chat_id
            },
            'monitoring': {
                'health_check_interval': config.health_check_interval
            },
            'api': {
                'retry_attempts': config.retry_attempts,
                'retry_delay': config.retry_delay
            }
        }
        
        # Ensure config directory exists
        os.makedirs(os.path.dirname(self.config_path), exist_ok=True)
        
        with open(self.config_path, 'w', encoding='utf-8') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True)
        
        self._config = config
    
    def _create_default_config(self) -> None:
        """Create default configuration file."""
        default_config = AppConfig()
        self.save_config(default_config)
    
    def update_marzban_config(self, base_url: str, username: str, password: str) -> None:
        """Update Marzban configuration."""
        config = self.load_config()
        config.marzban = MarzbanConfig(
            base_url=base_url,
            username=username,
            password=password
        )
        self.save_config(config)
    
    def is_marzban_configured(self) -> bool:
        """Check if Marzban is configured."""
        config = self.load_config()
        return (config.marzban is not None and 
                config.marzban.base_url and 
                config.marzban.username and 
                config.marzban.password)


# Global config manager instance
config_manager = ConfigManager()