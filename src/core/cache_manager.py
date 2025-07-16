"""Advanced caching system with SQLite backend and performance optimization."""

import asyncio
import sqlite3
import json
import time
import hashlib
from typing import Any, Dict, List, Optional, Union, Callable
from dataclasses import dataclass, asdict
from datetime import datetime, timedelta
from pathlib import Path
import threading

from .logger import get_logger
try:
    from .security import security_manager
except ImportError:
    security_manager = None


@dataclass
class CacheEntry:
    """Cache entry with metadata."""
    key: str
    value: Any
    created_at: datetime
    expires_at: Optional[datetime]
    access_count: int = 0
    last_accessed: Optional[datetime] = None
    tags: List[str] = None
    size_bytes: int = 0
    
    def __post_init__(self):
        if self.tags is None:
            self.tags = []
        if self.last_accessed is None:
            self.last_accessed = self.created_at


@dataclass
class CacheStats:
    """Cache statistics."""
    total_entries: int = 0
    total_size_bytes: int = 0
    hit_count: int = 0
    miss_count: int = 0
    eviction_count: int = 0
    
    @property
    def hit_rate(self) -> float:
        """Calculate cache hit rate."""
        total = self.hit_count + self.miss_count
        return (self.hit_count / total * 100) if total > 0 else 0.0


class CacheManager:
    """Advanced cache manager with SQLite backend."""
    
    def __init__(self, db_path: str = None, max_size_mb: int = 100):
        self.logger = get_logger("cache_manager")
        self.db_path = Path(db_path or "cache/cache.db")
        self.max_size_bytes = max_size_mb * 1024 * 1024
        self.stats = CacheStats()
        self._lock = threading.RLock()
        
        # Create cache directory
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        
        # Initialize database
        self._init_database()
        
        # Load existing stats
        self._load_stats()
        
        # Start cleanup task
        self._cleanup_task = None
        self._start_cleanup_task()
    
    def _init_database(self):
        """Initialize SQLite database."""
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.execute("""
                    CREATE TABLE IF NOT EXISTS cache_entries (
                        key TEXT PRIMARY KEY,
                        value TEXT NOT NULL,
                        created_at REAL NOT NULL,
                        expires_at REAL,
                        access_count INTEGER DEFAULT 0,
                        last_accessed REAL,
                        tags TEXT,
                        size_bytes INTEGER DEFAULT 0
                    )
                """)
                
                conn.execute("""
                    CREATE TABLE IF NOT EXISTS cache_stats (
                        id INTEGER PRIMARY KEY,
                        total_entries INTEGER DEFAULT 0,
                        total_size_bytes INTEGER DEFAULT 0,
                        hit_count INTEGER DEFAULT 0,
                        miss_count INTEGER DEFAULT 0,
                        eviction_count INTEGER DEFAULT 0,
                        updated_at REAL NOT NULL
                    )
                """)
                
                # Create indexes for performance
                conn.execute("CREATE INDEX IF NOT EXISTS idx_expires_at ON cache_entries(expires_at)")
                conn.execute("CREATE INDEX IF NOT EXISTS idx_last_accessed ON cache_entries(last_accessed)")
                conn.execute("CREATE INDEX IF NOT EXISTS idx_tags ON cache_entries(tags)")
                
                conn.commit()
                
            self.logger.debug("Cache database initialized")
            
        except Exception as e:
            self.logger.error(f"Failed to initialize cache database: {e}")
            raise
    
    def _load_stats(self):
        """Load cache statistics from database."""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.execute("SELECT * FROM cache_stats ORDER BY updated_at DESC LIMIT 1")
                row = cursor.fetchone()
                
                if row:
                    self.stats = CacheStats(
                        total_entries=row[1],
                        total_size_bytes=row[2],
                        hit_count=row[3],
                        miss_count=row[4],
                        eviction_count=row[5]
                    )
                
        except Exception as e:
            self.logger.warning(f"Failed to load cache stats: {e}")
    
    def _save_stats(self):
        """Save cache statistics to database."""
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.execute("""
                    INSERT INTO cache_stats 
                    (total_entries, total_size_bytes, hit_count, miss_count, eviction_count, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                """, (
                    self.stats.total_entries,
                    self.stats.total_size_bytes,
                    self.stats.hit_count,
                    self.stats.miss_count,
                    self.stats.eviction_count,
                    time.time()
                ))
                conn.commit()
                
        except Exception as e:
            self.logger.warning(f"Failed to save cache stats: {e}")
    
    def _serialize_value(self, value: Any) -> str:
        """Serialize value for storage."""
        try:
            if isinstance(value, (dict, list)):
                return json.dumps(value, default=str)
            elif isinstance(value, str):
                return value
            else:
                return json.dumps(value, default=str)
        except Exception as e:
            self.logger.warning(f"Failed to serialize value: {e}")
            return str(value)
    
    def _deserialize_value(self, value_str: str) -> Any:
        """Deserialize value from storage."""
        try:
            return json.loads(value_str)
        except json.JSONDecodeError:
            return value_str
        except Exception as e:
            self.logger.warning(f"Failed to deserialize value: {e}")
            return value_str
    
    def _calculate_size(self, value: Any) -> int:
        """Calculate approximate size of value in bytes."""
        try:
            serialized = self._serialize_value(value)
            return len(serialized.encode('utf-8'))
        except Exception:
            return len(str(value).encode('utf-8'))
    
    def _generate_key_hash(self, key: str) -> str:
        """Generate hash for key to handle long keys."""
        if len(key) <= 250:  # SQLite limit is 255
            return key
        return hashlib.sha256(key.encode()).hexdigest()
    
    async def get(self, key: str, default: Any = None) -> Any:
        """Get value from cache."""
        key_hash = self._generate_key_hash(key)
        
        try:
            with self._lock:
                with sqlite3.connect(self.db_path) as conn:
                    cursor = conn.execute("""
                        SELECT value, expires_at, access_count 
                        FROM cache_entries 
                        WHERE key = ?
                    """, (key_hash,))
                    
                    row = cursor.fetchone()
                    
                    if row is None:
                        self.stats.miss_count += 1
                        self.logger.debug(f"Cache miss: {key}")
                        return default
                    
                    value_str, expires_at, access_count = row
                    
                    # Check expiration
                    if expires_at and time.time() > expires_at:
                        await self.delete(key)
                        self.stats.miss_count += 1
                        self.logger.debug(f"Cache expired: {key}")
                        return default
                    
                    # Update access statistics
                    conn.execute("""
                        UPDATE cache_entries 
                        SET access_count = ?, last_accessed = ?
                        WHERE key = ?
                    """, (access_count + 1, time.time(), key_hash))
                    
                    conn.commit()
                    
                    self.stats.hit_count += 1
                    value = self._deserialize_value(value_str)
                    
                    self.logger.debug(f"Cache hit: {key}")
                    return value
                    
        except Exception as e:
            self.logger.error(f"Cache get error for key {key}: {e}")
            self.stats.miss_count += 1
            return default
    
    async def set(
        self, 
        key: str, 
        value: Any, 
        ttl: Optional[int] = None,
        tags: List[str] = None
    ) -> bool:
        """Set value in cache."""
        key_hash = self._generate_key_hash(key)
        
        try:
            with self._lock:
                # Calculate size and check limits
                size_bytes = self._calculate_size(value)
                
                # Check if we need to make space
                if self.stats.total_size_bytes + size_bytes > self.max_size_bytes:
                    await self._evict_entries(size_bytes)
                
                # Prepare data
                value_str = self._serialize_value(value)
                created_at = time.time()
                expires_at = created_at + ttl if ttl else None
                tags_str = json.dumps(tags) if tags else None
                
                with sqlite3.connect(self.db_path) as conn:
                    # Check if key exists
                    cursor = conn.execute("SELECT size_bytes FROM cache_entries WHERE key = ?", (key_hash,))
                    existing = cursor.fetchone()
                    
                    if existing:
                        # Update existing entry
                        old_size = existing[0]
                        conn.execute("""
                            UPDATE cache_entries 
                            SET value = ?, created_at = ?, expires_at = ?, 
                                access_count = 0, last_accessed = ?, tags = ?, size_bytes = ?
                            WHERE key = ?
                        """, (value_str, created_at, expires_at, created_at, tags_str, size_bytes, key_hash))
                        
                        self.stats.total_size_bytes += (size_bytes - old_size)
                    else:
                        # Insert new entry
                        conn.execute("""
                            INSERT INTO cache_entries 
                            (key, value, created_at, expires_at, last_accessed, tags, size_bytes)
                            VALUES (?, ?, ?, ?, ?, ?, ?)
                        """, (key_hash, value_str, created_at, expires_at, created_at, tags_str, size_bytes))
                        
                        self.stats.total_entries += 1
                        self.stats.total_size_bytes += size_bytes
                    
                    conn.commit()
                
                self.logger.debug(f"Cache set: {key} ({size_bytes} bytes)")
                return True
                
        except Exception as e:
            self.logger.error(f"Cache set error for key {key}: {e}")
            return False
    
    async def delete(self, key: str) -> bool:
        """Delete value from cache."""
        key_hash = self._generate_key_hash(key)
        
        try:
            with self._lock:
                with sqlite3.connect(self.db_path) as conn:
                    cursor = conn.execute("SELECT size_bytes FROM cache_entries WHERE key = ?", (key_hash,))
                    row = cursor.fetchone()
                    
                    if row:
                        size_bytes = row[0]
                        conn.execute("DELETE FROM cache_entries WHERE key = ?", (key_hash,))
                        conn.commit()
                        
                        self.stats.total_entries -= 1
                        self.stats.total_size_bytes -= size_bytes
                        
                        self.logger.debug(f"Cache delete: {key}")
                        return True
                    
                return False
                
        except Exception as e:
            self.logger.error(f"Cache delete error for key {key}: {e}")
            return False
    
    async def clear(self, tags: List[str] = None) -> int:
        """Clear cache entries, optionally by tags."""
        try:
            with self._lock:
                with sqlite3.connect(self.db_path) as conn:
                    if tags:
                        # Clear by tags
                        placeholders = ','.join('?' * len(tags))
                        cursor = conn.execute(f"""
                            SELECT COUNT(*), SUM(size_bytes) FROM cache_entries 
                            WHERE tags IN ({placeholders})
                        """, tags)
                        
                        result = cursor.fetchone()
                        count, total_size = result[0] or 0, result[1] or 0
                        
                        conn.execute(f"DELETE FROM cache_entries WHERE tags IN ({placeholders})", tags)
                        
                        self.stats.total_entries -= count
                        self.stats.total_size_bytes -= total_size
                        
                    else:
                        # Clear all
                        count = self.stats.total_entries
                        conn.execute("DELETE FROM cache_entries")
                        
                        self.stats.total_entries = 0
                        self.stats.total_size_bytes = 0
                    
                    conn.commit()
                    
                    self.logger.info(f"Cache cleared: {count} entries")
                    return count
                    
        except Exception as e:
            self.logger.error(f"Cache clear error: {e}")
            return 0
    
    async def _evict_entries(self, needed_bytes: int):
        """Evict entries to make space."""
        try:
            with sqlite3.connect(self.db_path) as conn:
                # Use LRU eviction strategy
                cursor = conn.execute("""
                    SELECT key, size_bytes FROM cache_entries 
                    ORDER BY last_accessed ASC
                """)
                
                freed_bytes = 0
                evicted_count = 0
                
                for row in cursor:
                    key, size_bytes = row
                    
                    conn.execute("DELETE FROM cache_entries WHERE key = ?", (key,))
                    
                    freed_bytes += size_bytes
                    evicted_count += 1
                    
                    if freed_bytes >= needed_bytes:
                        break
                
                conn.commit()
                
                self.stats.total_entries -= evicted_count
                self.stats.total_size_bytes -= freed_bytes
                self.stats.eviction_count += evicted_count
                
                self.logger.info(f"Evicted {evicted_count} entries, freed {freed_bytes} bytes")
                
        except Exception as e:
            self.logger.error(f"Cache eviction error: {e}")
    
    async def exists(self, key: str) -> bool:
        """Check if key exists in cache."""
        key_hash = self._generate_key_hash(key)
        
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.execute("""
                    SELECT expires_at FROM cache_entries WHERE key = ?
                """, (key_hash,))
                
                row = cursor.fetchone()
                
                if row is None:
                    return False
                
                expires_at = row[0]
                if expires_at and time.time() > expires_at:
                    await self.delete(key)
                    return False
                
                return True
                
        except Exception as e:
            self.logger.error(f"Cache exists error for key {key}: {e}")
            return False
    
    async def get_stats(self) -> CacheStats:
        """Get cache statistics."""
        return self.stats
    
    async def cleanup_expired(self) -> int:
        """Clean up expired entries."""
        try:
            with self._lock:
                current_time = time.time()
                
                with sqlite3.connect(self.db_path) as conn:
                    cursor = conn.execute("""
                        SELECT COUNT(*), SUM(size_bytes) FROM cache_entries 
                        WHERE expires_at IS NOT NULL AND expires_at < ?
                    """, (current_time,))
                    
                    result = cursor.fetchone()
                    count, total_size = result[0] or 0, result[1] or 0
                    
                    if count > 0:
                        conn.execute("""
                            DELETE FROM cache_entries 
                            WHERE expires_at IS NOT NULL AND expires_at < ?
                        """, (current_time,))
                        
                        conn.commit()
                        
                        self.stats.total_entries -= count
                        self.stats.total_size_bytes -= total_size
                        
                        self.logger.info(f"Cleaned up {count} expired entries")
                    
                    return count
                    
        except Exception as e:
            self.logger.error(f"Cache cleanup error: {e}")
            return 0
    
    def _start_cleanup_task(self):
        """Start background cleanup task."""
        async def cleanup_loop():
            while True:
                try:
                    await asyncio.sleep(300)  # 5 minutes
                    await self.cleanup_expired()
                    self._save_stats()
                except Exception as e:
                    self.logger.error(f"Cleanup task error: {e}")
        
        # Only start task if we're in an async context
        try:
            loop = asyncio.get_running_loop()
            self._cleanup_task = loop.create_task(cleanup_loop())
        except RuntimeError:
            # No event loop running, will start later
            self._cleanup_task = None
            self.logger.debug("No event loop running, cleanup task will start later")
    
    async def close(self):
        """Close cache manager."""
        if self._cleanup_task:
            self._cleanup_task.cancel()
            try:
                await self._cleanup_task
            except asyncio.CancelledError:
                pass
        
        self._save_stats()
        self.logger.info("Cache manager closed")


# Decorator for caching function results
def cached(ttl: int = 3600, tags: List[str] = None, key_prefix: str = ""):
    """Decorator for caching function results."""
    def decorator(func: Callable):
        async def wrapper(*args, **kwargs):
            # Generate cache key
            key_parts = [key_prefix, func.__name__]
            key_parts.extend(str(arg) for arg in args)
            key_parts.extend(f"{k}={v}" for k, v in sorted(kwargs.items()))
            cache_key = ":".join(filter(None, key_parts))
            
            # Try to get from cache
            cached_result = await cache_manager.get(cache_key)
            if cached_result is not None:
                return cached_result
            
            # Execute function and cache result
            result = await func(*args, **kwargs)
            await cache_manager.set(cache_key, result, ttl=ttl, tags=tags)
            
            return result
        
        return wrapper
    return decorator


# Simple cache manager without async tasks for import safety
class SimpleCacheManager:
    """Simple cache manager without async tasks."""
    
    def __init__(self):
        self.cache = {}
        self.logger = get_logger("simple_cache")
    
    async def get(self, key: str, default=None):
        return self.cache.get(key, default)
    
    async def set(self, key: str, value, ttl=None, tags=None):
        self.cache[key] = value
        return True
    
    async def delete(self, key: str):
        return self.cache.pop(key, None) is not None
    
    async def clear(self, tags=None):
        count = len(self.cache)
        self.cache.clear()
        return count
    
    async def exists(self, key: str):
        return key in self.cache
    
    async def get_stats(self):
        return {"entries": len(self.cache)}
    
    async def close(self):
        pass

# Global cache manager instance (simple version for import safety)
cache_manager = SimpleCacheManager()

def get_cache_manager():
    """Get global cache manager instance."""
    return cache_manager