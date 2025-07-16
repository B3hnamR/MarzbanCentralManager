# 👨‍💻 Developer Guide - Marzban Central Manager

## 🎯 راهنمای توسعه‌دهندگان

این راهنما برای توسعه‌دهندگانی که می‌خواهند در پروژه مشارکت کنند یا فیچرهای جدید اضافه کنند، طراحی شده است.

---

## 🏗️ معماری کلی

### 📊 Stack تکنولوژی

```python
# Backend
Python 3.8+           # زبان اصلی
asyncio              # Async programming
httpx                # HTTP client
click                # CLI framework
pyyaml               # Configuration
psutil               # System monitoring
netifaces            # Network discovery

# Security
cryptography         # Encryption
pyjwt                # JWT tokens

# Development
pytest               # Testing
black                # Code formatting
flake8               # Linting
```

### 🏛️ لایه‌های معماری

```
┌─────────────────────────────────────┐
│           Presentation Layer        │  ← CLI, Interactive Menu
├─────────────────────────────────────┤
│          Business Logic Layer       │  ← Services
├─────────────────────────────────────┤
│             API Layer               │  ← HTTP Client, Endpoints
├─────────────────────────────────────┤
│             Core Layer              │  ← Utils, Config, Logger
└─────────────────────────────────────┘
```

---

## 🚀 محیط توسعه

### 📦 نصب محیط توسعه

```bash
# Clone repository
git clone https://github.com/B3hnamR/MarzbanCentralManager.git
cd MarzbanCentralManager

# Create virtual environment
python -m venv venv
source venv/bin/activate  # Linux/Mac
# venv\Scripts\activate   # Windows

# Install dependencies
pip install -r requirements.txt

# Install development dependencies
pip install pytest pytest-asyncio black flake8
```

### 🔧 تنظیمات IDE

#### VS Code
```json
// .vscode/settings.json
{
    "python.defaultInterpreterPath": "./venv/bin/python",
    "python.linting.enabled": true,
    "python.linting.flake8Enabled": true,
    "python.formatting.provider": "black",
    "python.formatting.blackArgs": ["--line-length=88"],
    "python.testing.pytestEnabled": true
}
```

#### PyCharm
- Interpreter: Project venv
- Code style: Black
- Linter: flake8
- Test runner: pytest

---

## 📝 استانداردهای کدنویسی

### 🎨 Code Style

```python
# استفاده از Black formatter
black --line-length=88 src/

# استفاده از flake8 linter
flake8 src/ --max-line-length=88

# Type hints الزامی
def process_node(node_id: int) -> Optional[Node]:
    """Process a node and return result."""
    pass

# Docstrings برای همه functions/classes
class NodeService:
    """Service for managing Marzban nodes.
    
    This service provides CRUD operations and monitoring
    capabilities for Marzban nodes.
    """
    
    async def create_node(self, name: str, address: str) -> Node:
        """Create a new node.
        
        Args:
            name: Human-readable name for the node
            address: IP address or hostname of the node
            
        Returns:
            Created node instance
            
        Raises:
            ValidationError: If input data is invalid
            APIError: If API call fails
        """
        pass
```

### 📁 ساختار فایل‌ها

```python
# هر فایل Python باید این ساختار را داشته باشد:

"""Module description.

Detailed description of what this module does.
"""

import asyncio
import logging
from typing import Optional, Dict, Any

from ..core.logger import get_logger
from ..core.exceptions import CustomError


class ExampleClass:
    """Example class with proper structure."""
    
    def __init__(self):
        self.logger = get_logger(self.__class__.__name__)
    
    async def example_method(self) -> Dict[str, Any]:
        """Example async method."""
        try:
            # Implementation
            result = await self._do_something()
            self.logger.info("Operation completed successfully")
            return result
        except Exception as e:
            self.logger.error(f"Operation failed: {e}")
            raise
    
    async def _do_something(self) -> Dict[str, Any]:
        """Private helper method."""
        pass
```

---

## 🔧 اضافه کردن فیچر جدید

### 1️⃣ ایجاد Service جدید

```python
# src/services/new_feature_service.py
"""Service for new feature functionality."""

import asyncio
from typing import List, Optional, Dict, Any

from ..core.logger import get_logger
from ..core.exceptions import ServiceError
from ..api.endpoints.new_endpoint import NewEndpointAPI


class NewFeatureService:
    """Service for managing new feature."""
    
    def __init__(self):
        self.logger = get_logger("new_feature_service")
        self._api: Optional[NewEndpointAPI] = None
    
    async def _get_api(self) -> NewEndpointAPI:
        """Get API client instance."""
        if not self._api:
            from ..core.config import config_manager
            config = config_manager.load_config()
            self._api = NewEndpointAPI(config.marzban)
        return self._api
    
    async def new_operation(self, param: str) -> Dict[str, Any]:
        """Perform new operation.
        
        Args:
            param: Operation parameter
            
        Returns:
            Operation result
            
        Raises:
            ServiceError: If operation fails
        """
        try:
            self.logger.info(f"Starting new operation with param: {param}")
            api = await self._get_api()
            
            result = await api.call_new_endpoint(param)
            
            self.logger.info("New operation completed successfully")
            return result
            
        except Exception as e:
            self.logger.error(f"New operation failed: {e}")
            raise ServiceError(f"Failed to perform new operation: {e}")
    
    async def close(self):
        """Close service and cleanup resources."""
        if self._api:
            await self._api.close()
            self._api = None
```

### 2️⃣ اضافه کردن API Endpoint

```python
# src/api/endpoints/new_endpoint.py
"""API endpoints for new feature."""

from typing import Dict, Any

from ..base import BaseAPIClient


class NewEndpointAPI(BaseAPIClient):
    """API client for new feature endpoints."""
    
    async def call_new_endpoint(self, param: str) -> Dict[str, Any]:
        """Call new API endpoint.
        
        Args:
            param: Request parameter
            
        Returns:
            API response data
        """
        self.logger.info(f"Calling new endpoint with param: {param}")
        
        response = await self.post("new-endpoint", {
            "parameter": param
        })
        
        self.logger.info("New endpoint call successful")
        return response
    
    async def get_new_data(self) -> List[Dict[str, Any]]:
        """Get data from new endpoint."""
        self.logger.info("Fetching new data")
        
        response = await self.get("new-data")
        
        self.logger.info(f"Retrieved {len(response)} items")
        return response
```

### 3️⃣ اضافه کردن CLI Command

```python
# src/cli/commands/new_feature.py
"""CLI commands for new feature."""

import asyncio
import click
from typing import Optional

from ...services.new_feature_service import NewFeatureService


@click.group()
def new_feature():
    """New feature management commands."""
    pass


@new_feature.command()
@click.argument('param')
@click.option('--option', '-o', help='Optional parameter')
async def operation(param: str, option: Optional[str]):
    """Perform new operation.
    
    Args:
        param: Required parameter
        option: Optional parameter
    """
    service = NewFeatureService()
    
    try:
        click.echo(f"🚀 Starting new operation with param: {param}")
        
        result = await service.new_operation(param)
        
        click.echo("✅ Operation completed successfully!")
        click.echo(f"Result: {result}")
        
    except Exception as e:
        click.echo(f"❌ Operation failed: {e}")
    
    finally:
        await service.close()


@new_feature.command()
async def list_data():
    """List new feature data."""
    service = NewFeatureService()
    
    try:
        click.echo("📋 Fetching data...")
        
        # Implementation here
        
    except Exception as e:
        click.echo(f"❌ Failed to fetch data: {e}")
    
    finally:
        await service.close()


# Register command group in main.py
# cli.add_command(new_feature)
```

### 4️⃣ اضافه کردن به Interactive Menu

```python
# در src/cli/ui/menus.py

# اضافه کردن به menu definitions
"new_feature": {
    "title": "🆕 New Feature",
    "subtitle": "Manage new feature functionality",
    "options": [
        {"key": "1", "title": "🚀 Perform Operation", "action": self._new_feature_operation},
        {"key": "2", "title": "📋 List Data", "action": self._new_feature_list},
        {"key": "0", "title": "🔙 Back to Main Menu", "action": self._goto_main_menu},
    ]
}

# اضافه کردن navigation method
def _goto_new_feature_menu(self):
    """Go to new feature menu."""
    self.current_menu = "new_feature"

# اضافه کردن implementation methods
async def _new_feature_operation(self):
    """Perform new feature operation."""
    try:
        from ...services.new_feature_service import NewFeatureService
        
        clear_screen()
        display_header("🚀 New Feature Operation")
        
        param = prompt_for_input("Enter parameter")
        
        service = NewFeatureService()
        
        info_message(f"Performing operation with: {param}")
        result = await service.new_operation(param)
        
        success_message("Operation completed successfully!")
        
        # Display result
        display_key_value_pairs(result)
        
        await service.close()
        
    except Exception as e:
        error_message(f"Operation failed: {e}")
    
    pause()
```

---

## 🧪 تست‌نویسی

### 📝 ساختار تست‌ها

```python
# tests/unit/services/test_new_feature_service.py
"""Tests for NewFeatureService."""

import pytest
from unittest.mock import AsyncMock, patch

from src.services.new_feature_service import NewFeatureService
from src.core.exceptions import ServiceError


class TestNewFeatureService:
    """Test cases for NewFeatureService."""
    
    @pytest.fixture
    async def service(self):
        """Create service instance for testing."""
        service = NewFeatureService()
        yield service
        await service.close()
    
    @pytest.mark.asyncio
    async def test_new_operation_success(self, service):
        """Test successful new operation."""
        # Mock API response
        mock_api = AsyncMock()
        mock_api.call_new_endpoint.return_value = {"status": "success"}
        
        with patch.object(service, '_get_api', return_value=mock_api):
            result = await service.new_operation("test_param")
            
            assert result["status"] == "success"
            mock_api.call_new_endpoint.assert_called_once_with("test_param")
    
    @pytest.mark.asyncio
    async def test_new_operation_failure(self, service):
        """Test failed new operation."""
        mock_api = AsyncMock()
        mock_api.call_new_endpoint.side_effect = Exception("API Error")
        
        with patch.object(service, '_get_api', return_value=mock_api):
            with pytest.raises(ServiceError):
                await service.new_operation("test_param")


# اجرای تست‌ها
# pytest tests/unit/services/test_new_feature_service.py -v
```

### 🔄 Integration Tests

```python
# tests/integration/test_new_feature_integration.py
"""Integration tests for new feature."""

import pytest
from src.services.new_feature_service import NewFeatureService


@pytest.mark.integration
@pytest.mark.asyncio
async def test_new_feature_end_to_end():
    """Test complete new feature workflow."""
    service = NewFeatureService()
    
    try:
        # Test complete workflow
        result = await service.new_operation("integration_test")
        assert result is not None
        
    finally:
        await service.close()
```

---

## 📊 مانیتورینگ و لاگ

### 📝 استفاده از Logger

```python
from ..core.logger import get_logger

class ExampleService:
    def __init__(self):
        self.logger = get_logger("example_service")
    
    async def example_method(self):
        # سطوح مختلف لاگ
        self.logger.debug("Debug information")
        self.logger.info("General information")
        self.logger.warning("Warning message")
        self.logger.error("Error occurred")
        
        # لاگ با context
        self.logger.info("Processing node", extra={
            "node_id": 123,
            "operation": "update"
        })
```

### 📈 اضافه کردن Metrics

```python
# در services
class ExampleService:
    def __init__(self):
        self.stats = {
            "operations_count": 0,
            "success_count": 0,
            "error_count": 0
        }
    
    async def example_operation(self):
        self.stats["operations_count"] += 1
        
        try:
            # انجام عملیات
            result = await self._do_operation()
            self.stats["success_count"] += 1
            return result
            
        except Exception as e:
            self.stats["error_count"] += 1
            raise
    
    def get_stats(self) -> Dict[str, int]:
        """Get service statistics."""
        return self.stats.copy()
```

---

## 🔒 امنیت

### 🛡️ اصول امنیتی

```python
# 1. Input Validation
def validate_input(data: str) -> bool:
    """Validate user input."""
    if not data or len(data) > 255:
        return False
    
    # Check for malicious patterns
    dangerous_patterns = ['<script>', 'DROP TABLE', '--']
    return not any(pattern in data.lower() for pattern in dangerous_patterns)

# 2. Sensitive Data Handling
def mask_password(password: str) -> str:
    """Mask password for logging."""
    if len(password) <= 4:
        return "*" * len(password)
    return password[:2] + "*" * (len(password) - 4) + password[-2:]

# 3. Error Handling
try:
    result = await api_call()
except APIError as e:
    # Don't expose internal details
    self.logger.error(f"API call failed: {e}")
    raise ServiceError("Operation failed")
```

---

## 🚀 Performance

### ⚡ بهینه‌سازی

```python
# 1. Async Operations
async def process_multiple_nodes(node_ids: List[int]):
    """Process multiple nodes concurrently."""
    tasks = [process_single_node(node_id) for node_id in node_ids]
    results = await asyncio.gather(*tasks, return_exceptions=True)
    return results

# 2. Caching
from ..core.cache_manager import cache_manager

async def get_node_data(node_id: int):
    """Get node data with caching."""
    cache_key = f"node_data_{node_id}"
    
    # Try cache first
    cached_data = await cache_manager.get(cache_key)
    if cached_data:
        return cached_data
    
    # Fetch from API
    data = await api.get_node(node_id)
    
    # Cache for 5 minutes
    await cache_manager.set(cache_key, data, ttl=300)
    
    return data

# 3. Connection Pooling
# استفاده از connection_manager برای HTTP requests
```

---

## 📚 مستندات

### 📝 نوشتن مستندات

```python
def complex_function(param1: str, param2: Optional[int] = None) -> Dict[str, Any]:
    """Perform complex operation.
    
    This function does something complex with the provided parameters
    and returns a structured result.
    
    Args:
        param1: Primary parameter for the operation
        param2: Optional secondary parameter (default: None)
    
    Returns:
        Dictionary containing:
            - status: Operation status ('success' or 'error')
            - data: Result data if successful
            - message: Human-readable message
    
    Raises:
        ValueError: If param1 is empty or invalid
        ServiceError: If the operation fails
    
    Example:
        >>> result = complex_function("test", 42)
        >>> print(result['status'])
        'success'
    """
    pass
```

---

## 🔄 CI/CD

### 🤖 GitHub Actions

```yaml
# .github/workflows/test.yml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v2
    
    - name: Set up Python
      uses: actions/setup-python@v2
      with:
        python-version: 3.8
    
    - name: Install dependencies
      run: |
        pip install -r requirements.txt
        pip install pytest pytest-asyncio black flake8
    
    - name: Lint with flake8
      run: flake8 src/ --max-line-length=88
    
    - name: Format check with black
      run: black --check src/
    
    - name: Test with pytest
      run: pytest tests/ -v
```

---

## 🐛 Debugging

### 🔍 تکنیک‌های Debug

```python
# 1. استفاده از pdb
import pdb

async def debug_function():
    data = await get_data()
    pdb.set_trace()  # Breakpoint
    processed = process_data(data)
    return processed

# 2. Logging برای Debug
self.logger.debug("Function called with args: %s", args)
self.logger.debug("Intermediate result: %s", intermediate_result)

# 3. Exception Handling
try:
    result = await risky_operation()
except Exception as e:
    self.logger.exception("Detailed error information:")
    raise
```

---

## 📋 Checklist برای PR

### ✅ قبل از ارسال Pull Request

- [ ] کد با Black فرمت شده
- [ ] Flake8 بدون خطا
- [ ] Type hints اضافه شده
- [ ] Docstrings نوشته شده
- [ ] تست‌های unit نوشته شده
- [ ] تست‌های integration (در صورت نیاز)
- [ ] مستندات به‌روزرسانی شده
- [ ] CHANGELOG.md به‌روزرسانی شده
- [ ] تست‌ها پاس می‌شوند

### 📝 Template برای PR

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Manual testing completed

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] Tests pass
```

---

## 🎯 نکات مهم

### 💡 Best Practices

1. **همیشه async/await استفاده کنید** برای I/O operations
2. **Error handling جامع** در همه سطوح
3. **Logging مناسب** برای debugging
4. **Type hints** برای همه functions
5. **Docstrings** برای همه public methods
6. **Unit tests** برای منطق کسب و کار
7. **Integration tests** برای workflow کامل

### 🚫 اشتباهات رایج

1. **Blocking I/O** در async functions
2. **عدم استفاده از connection pooling**
3. **Hard-coding** values به جای config
4. **عدم validation** ورودی‌ها
5. **Logging** اطلاعات حساس
6. **عدم cleanup** resources

---

## 📞 دریافت کمک

### 🤝 مشارکت

- Fork کردن repository
- ایجاد feature branch
- Commit کردن تغییرات
- Push کردن به branch
- ایجاد Pull Request

### 💬 ارتباط

- GitHub Issues برای bug reports
- GitHub Discussions برای سوالات
- Email: behnamrjd@gmail.com

---

**موفق باشید در توسعه! 🚀**