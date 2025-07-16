"""Security and encryption utilities for Marzban Central Manager."""

import os
import base64
import hashlib
import secrets
from typing import Optional, Dict, Any
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from pathlib import Path

from .logger import get_logger


class SecurityManager:
    """Manages encryption, decryption and secure storage."""
    
    def __init__(self, config_dir: str = None):
        self.logger = get_logger("security")
        self.config_dir = Path(config_dir or os.path.expanduser("~/.marzban_manager"))
        self.config_dir.mkdir(parents=True, exist_ok=True)
        
        self.key_file = self.config_dir / ".security_key"
        self.salt_file = self.config_dir / ".salt"
        
        # Set secure permissions
        os.chmod(self.config_dir, 0o700)
        
        self._fernet = None
        self._initialize_encryption()
    
    def _initialize_encryption(self):
        """Initialize encryption system."""
        try:
            # Generate or load salt
            if not self.salt_file.exists():
                salt = os.urandom(16)
                with open(self.salt_file, 'wb') as f:
                    f.write(salt)
                os.chmod(self.salt_file, 0o600)
            else:
                with open(self.salt_file, 'rb') as f:
                    salt = f.read()
            
            # Generate or load encryption key
            if not self.key_file.exists():
                # Generate master password if not exists
                master_password = self._generate_master_password()
                key = self._derive_key(master_password, salt)
                
                # Store encrypted key
                with open(self.key_file, 'wb') as f:
                    f.write(key)
                os.chmod(self.key_file, 0o600)
                
                self.logger.info("New encryption key generated")
            else:
                with open(self.key_file, 'rb') as f:
                    key = f.read()
            
            self._fernet = Fernet(key)
            self.logger.debug("Encryption system initialized")
            
        except Exception as e:
            self.logger.error(f"Failed to initialize encryption: {e}")
            raise
    
    def _generate_master_password(self) -> str:
        """Generate a secure master password."""
        # Use system entropy for master password
        password = secrets.token_urlsafe(32)
        
        # Store in a secure location (you might want to prompt user for this)
        master_file = self.config_dir / ".master"
        with open(master_file, 'w') as f:
            f.write(password)
        os.chmod(master_file, 0o600)
        
        return password
    
    def _derive_key(self, password: str, salt: bytes) -> bytes:
        """Derive encryption key from password."""
        kdf = PBKDF2HMAC(
            algorithm=hashes.SHA256(),
            length=32,
            salt=salt,
            iterations=100000,
        )
        key = base64.urlsafe_b64encode(kdf.derive(password.encode()))
        return key
    
    def encrypt(self, data: str) -> str:
        """Encrypt sensitive data."""
        try:
            if not data:
                return ""
            
            encrypted_data = self._fernet.encrypt(data.encode())
            return base64.urlsafe_b64encode(encrypted_data).decode()
            
        except Exception as e:
            self.logger.error(f"Encryption failed: {e}")
            raise
    
    def decrypt(self, encrypted_data: str) -> str:
        """Decrypt sensitive data."""
        try:
            if not encrypted_data:
                return ""
            
            decoded_data = base64.urlsafe_b64decode(encrypted_data.encode())
            decrypted_data = self._fernet.decrypt(decoded_data)
            return decrypted_data.decode()
            
        except Exception as e:
            self.logger.error(f"Decryption failed: {e}")
            raise
    
    def hash_password(self, password: str) -> str:
        """Create secure hash of password."""
        salt = os.urandom(32)
        pwdhash = hashlib.pbkdf2_hmac('sha256', password.encode('utf-8'), salt, 100000)
        return base64.b64encode(salt + pwdhash).decode('ascii')
    
    def verify_password(self, password: str, hashed: str) -> bool:
        """Verify password against hash."""
        try:
            decoded = base64.b64decode(hashed.encode('ascii'))
            salt = decoded[:32]
            stored_hash = decoded[32:]
            pwdhash = hashlib.pbkdf2_hmac('sha256', password.encode('utf-8'), salt, 100000)
            return pwdhash == stored_hash
        except Exception:
            return False
    
    def mask_sensitive_data(self, data: str, visible_chars: int = 4) -> str:
        """Mask sensitive data for logging."""
        if not data or len(data) <= visible_chars * 2:
            return "*" * len(data) if data else ""
        
        start = data[:visible_chars]
        end = data[-visible_chars:]
        middle = "*" * (len(data) - visible_chars * 2)
        
        return f"{start}{middle}{end}"
    
    def generate_secure_token(self, length: int = 32) -> str:
        """Generate cryptographically secure token."""
        return secrets.token_urlsafe(length)
    
    def secure_delete_file(self, file_path: Path):
        """Securely delete a file by overwriting it."""
        try:
            if file_path.exists():
                # Overwrite with random data multiple times
                file_size = file_path.stat().st_size
                
                with open(file_path, 'r+b') as f:
                    for _ in range(3):  # 3 passes
                        f.seek(0)
                        f.write(os.urandom(file_size))
                        f.flush()
                        os.fsync(f.fileno())
                
                # Finally delete the file
                file_path.unlink()
                self.logger.debug(f"Securely deleted file: {file_path}")
                
        except Exception as e:
            self.logger.error(f"Failed to securely delete file {file_path}: {e}")


class SecureConfigManager:
    """Manages secure configuration storage."""
    
    def __init__(self, config_file: str):
        self.config_file = Path(config_file)
        self.security = SecurityManager()
        self.logger = get_logger("secure_config")
        
        # Sensitive fields that should be encrypted
        self.sensitive_fields = {
            'marzban.password',
            'telegram.bot_token',
            'telegram.chat_id',
            'database.password',
            'api.secret_key'
        }
    
    def save_config(self, config_data: Dict[str, Any]) -> bool:
        """Save configuration with encryption for sensitive data."""
        try:
            encrypted_config = self._encrypt_sensitive_fields(config_data)
            
            # Create backup of existing config
            if self.config_file.exists():
                backup_file = self.config_file.with_suffix('.bak')
                self.config_file.rename(backup_file)
            
            # Write new config
            import yaml
            with open(self.config_file, 'w', encoding='utf-8') as f:
                yaml.dump(encrypted_config, f, default_flow_style=False, allow_unicode=True)
            
            # Set secure permissions
            os.chmod(self.config_file, 0o600)
            
            self.logger.info("Configuration saved securely")
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to save secure config: {e}")
            return False
    
    def load_config(self) -> Dict[str, Any]:
        """Load configuration and decrypt sensitive data."""
        try:
            if not self.config_file.exists():
                return {}
            
            import yaml
            with open(self.config_file, 'r', encoding='utf-8') as f:
                encrypted_config = yaml.safe_load(f) or {}
            
            decrypted_config = self._decrypt_sensitive_fields(encrypted_config)
            
            self.logger.debug("Configuration loaded and decrypted")
            return decrypted_config
            
        except Exception as e:
            self.logger.error(f"Failed to load secure config: {e}")
            return {}
    
    def _encrypt_sensitive_fields(self, config: Dict[str, Any]) -> Dict[str, Any]:
        """Encrypt sensitive fields in configuration."""
        encrypted_config = config.copy()
        
        for field_path in self.sensitive_fields:
            value = self._get_nested_value(encrypted_config, field_path)
            if value:
                encrypted_value = self.security.encrypt(str(value))
                self._set_nested_value(encrypted_config, field_path, f"encrypted:{encrypted_value}")
        
        return encrypted_config
    
    def _decrypt_sensitive_fields(self, config: Dict[str, Any]) -> Dict[str, Any]:
        """Decrypt sensitive fields in configuration."""
        decrypted_config = config.copy()
        
        for field_path in self.sensitive_fields:
            value = self._get_nested_value(decrypted_config, field_path)
            if value and str(value).startswith("encrypted:"):
                encrypted_value = str(value)[10:]  # Remove "encrypted:" prefix
                try:
                    decrypted_value = self.security.decrypt(encrypted_value)
                    self._set_nested_value(decrypted_config, field_path, decrypted_value)
                except Exception as e:
                    self.logger.error(f"Failed to decrypt field {field_path}: {e}")
        
        return decrypted_config
    
    def _get_nested_value(self, data: Dict[str, Any], path: str) -> Any:
        """Get value from nested dictionary using dot notation."""
        keys = path.split('.')
        current = data
        
        for key in keys:
            if isinstance(current, dict) and key in current:
                current = current[key]
            else:
                return None
        
        return current
    
    def _set_nested_value(self, data: Dict[str, Any], path: str, value: Any):
        """Set value in nested dictionary using dot notation."""
        keys = path.split('.')
        current = data
        
        for key in keys[:-1]:
            if key not in current:
                current[key] = {}
            current = current[key]
        
        current[keys[-1]] = value


# Global security manager instance
security_manager = SecurityManager()