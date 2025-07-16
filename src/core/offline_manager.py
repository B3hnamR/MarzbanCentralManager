"""Offline mode management and data synchronization system."""

import asyncio
import json
import time
from typing import Dict, List, Optional, Any, Callable
from dataclasses import dataclass, asdict
from datetime import datetime, timedelta
from enum import Enum
import sqlite3
from pathlib import Path

from .logger import get_logger
from .cache_manager import cache_manager


class SyncStatus(Enum):
    """Synchronization status."""
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    FAILED = "failed"
    CONFLICT = "conflict"


class OperationType(Enum):
    """Types of operations that can be queued."""
    CREATE = "create"
    UPDATE = "update"
    DELETE = "delete"
    BULK_CREATE = "bulk_create"
    BULK_UPDATE = "bulk_update"
    BULK_DELETE = "bulk_delete"


@dataclass
class QueuedOperation:
    """Queued operation for offline mode."""
    id: str
    operation_type: OperationType
    resource_type: str  # 'node', 'user', etc.
    resource_id: Optional[str]
    data: Dict[str, Any]
    created_at: datetime
    retry_count: int = 0
    max_retries: int = 3
    status: SyncStatus = SyncStatus.PENDING
    error_message: Optional[str] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for storage."""
        return {
            'id': self.id,
            'operation_type': self.operation_type.value,
            'resource_type': self.resource_type,
            'resource_id': self.resource_id,
            'data': json.dumps(self.data),
            'created_at': self.created_at.timestamp(),
            'retry_count': self.retry_count,
            'max_retries': self.max_retries,
            'status': self.status.value,
            'error_message': self.error_message
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'QueuedOperation':
        """Create from dictionary."""
        return cls(
            id=data['id'],
            operation_type=OperationType(data['operation_type']),
            resource_type=data['resource_type'],
            resource_id=data['resource_id'],
            data=json.loads(data['data']),
            created_at=datetime.fromtimestamp(data['created_at']),
            retry_count=data['retry_count'],
            max_retries=data['max_retries'],
            status=SyncStatus(data['status']),
            error_message=data['error_message']
        )


@dataclass
class SyncStats:
    """Synchronization statistics."""
    total_operations: int = 0
    pending_operations: int = 0
    completed_operations: int = 0
    failed_operations: int = 0
    last_sync_time: Optional[datetime] = None
    is_online: bool = True
    
    @property
    def success_rate(self) -> float:
        """Calculate sync success rate."""
        total = self.completed_operations + self.failed_operations
        return (self.completed_operations / total * 100) if total > 0 else 0.0


class OfflineManager:
    """Manages offline mode and data synchronization."""
    
    def __init__(self, db_path: str = None):
        self.logger = get_logger("offline_manager")
        self.db_path = Path(db_path or "cache/offline.db")
        self.is_online = True
        self.sync_handlers: Dict[str, Callable] = {}
        self.stats = SyncStats()
        
        # Create database directory
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        
        # Initialize database
        self._init_database()
        
        # Load stats
        self._load_stats()
        
        # Start sync task
        self._sync_task = None
        self._start_sync_task()
    
    def _init_database(self):
        """Initialize SQLite database for offline operations."""
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.execute("""
                    CREATE TABLE IF NOT EXISTS queued_operations (
                        id TEXT PRIMARY KEY,
                        operation_type TEXT NOT NULL,
                        resource_type TEXT NOT NULL,
                        resource_id TEXT,
                        data TEXT NOT NULL,
                        created_at REAL NOT NULL,
                        retry_count INTEGER DEFAULT 0,
                        max_retries INTEGER DEFAULT 3,
                        status TEXT DEFAULT 'pending',
                        error_message TEXT
                    )
                """)
                
                conn.execute("""
                    CREATE TABLE IF NOT EXISTS sync_stats (
                        id INTEGER PRIMARY KEY,
                        total_operations INTEGER DEFAULT 0,
                        pending_operations INTEGER DEFAULT 0,
                        completed_operations INTEGER DEFAULT 0,
                        failed_operations INTEGER DEFAULT 0,
                        last_sync_time REAL,
                        is_online BOOLEAN DEFAULT 1,
                        updated_at REAL NOT NULL
                    )
                """)
                
                # Create indexes
                conn.execute("CREATE INDEX IF NOT EXISTS idx_status ON queued_operations(status)")
                conn.execute("CREATE INDEX IF NOT EXISTS idx_resource_type ON queued_operations(resource_type)")
                conn.execute("CREATE INDEX IF NOT EXISTS idx_created_at ON queued_operations(created_at)")
                
                conn.commit()
                
            self.logger.debug("Offline database initialized")
            
        except Exception as e:
            self.logger.error(f"Failed to initialize offline database: {e}")
            raise
    
    def _load_stats(self):
        """Load synchronization statistics."""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.execute("SELECT * FROM sync_stats ORDER BY updated_at DESC LIMIT 1")
                row = cursor.fetchone()
                
                if row:
                    self.stats = SyncStats(
                        total_operations=row[1],
                        pending_operations=row[2],
                        completed_operations=row[3],
                        failed_operations=row[4],
                        last_sync_time=datetime.fromtimestamp(row[5]) if row[5] else None,
                        is_online=bool(row[6])
                    )
                    self.is_online = self.stats.is_online
                
                # Update pending count from actual data
                cursor = conn.execute("SELECT COUNT(*) FROM queued_operations WHERE status = 'pending'")
                self.stats.pending_operations = cursor.fetchone()[0]
                
        except Exception as e:
            self.logger.warning(f"Failed to load sync stats: {e}")
    
    def _save_stats(self):
        """Save synchronization statistics."""
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.execute("""
                    INSERT INTO sync_stats 
                    (total_operations, pending_operations, completed_operations, 
                     failed_operations, last_sync_time, is_online, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, (
                    self.stats.total_operations,
                    self.stats.pending_operations,
                    self.stats.completed_operations,
                    self.stats.failed_operations,
                    self.stats.last_sync_time.timestamp() if self.stats.last_sync_time else None,
                    self.is_online,
                    time.time()
                ))
                conn.commit()
                
        except Exception as e:
            self.logger.warning(f"Failed to save sync stats: {e}")
    
    def register_sync_handler(self, resource_type: str, handler: Callable):
        """Register synchronization handler for resource type."""
        self.sync_handlers[resource_type] = handler
        self.logger.debug(f"Registered sync handler for {resource_type}")
    
    async def queue_operation(
        self,
        operation_type: OperationType,
        resource_type: str,
        data: Dict[str, Any],
        resource_id: Optional[str] = None
    ) -> str:
        """Queue an operation for later synchronization."""
        import uuid
        
        operation_id = str(uuid.uuid4())
        operation = QueuedOperation(
            id=operation_id,
            operation_type=operation_type,
            resource_type=resource_type,
            resource_id=resource_id,
            data=data,
            created_at=datetime.now()
        )
        
        try:
            with sqlite3.connect(self.db_path) as conn:
                op_dict = operation.to_dict()
                conn.execute("""
                    INSERT INTO queued_operations 
                    (id, operation_type, resource_type, resource_id, data, 
                     created_at, retry_count, max_retries, status, error_message)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    op_dict['id'], op_dict['operation_type'], op_dict['resource_type'],
                    op_dict['resource_id'], op_dict['data'], op_dict['created_at'],
                    op_dict['retry_count'], op_dict['max_retries'], op_dict['status'],
                    op_dict['error_message']
                ))
                conn.commit()
            
            self.stats.total_operations += 1
            self.stats.pending_operations += 1
            
            self.logger.info(f"Queued operation: {operation_type.value} {resource_type} ({operation_id})")
            
            # Try immediate sync if online
            if self.is_online:
                asyncio.create_task(self._sync_single_operation(operation))
            
            return operation_id
            
        except Exception as e:
            self.logger.error(f"Failed to queue operation: {e}")
            raise
    
    async def _sync_single_operation(self, operation: QueuedOperation) -> bool:
        """Synchronize a single operation."""
        if operation.resource_type not in self.sync_handlers:
            self.logger.error(f"No sync handler for resource type: {operation.resource_type}")
            return False
        
        try:
            handler = self.sync_handlers[operation.resource_type]
            
            # Update status to in progress
            await self._update_operation_status(operation.id, SyncStatus.IN_PROGRESS)
            
            # Execute the operation
            success = await handler(operation)
            
            if success:
                await self._update_operation_status(operation.id, SyncStatus.COMPLETED)
                self.stats.completed_operations += 1
                self.stats.pending_operations -= 1
                
                self.logger.info(f"Synced operation: {operation.id}")
                return True
            else:
                # Increment retry count
                operation.retry_count += 1
                
                if operation.retry_count >= operation.max_retries:
                    await self._update_operation_status(operation.id, SyncStatus.FAILED, "Max retries exceeded")
                    self.stats.failed_operations += 1
                    self.stats.pending_operations -= 1
                else:
                    await self._update_operation_status(operation.id, SyncStatus.PENDING)
                
                return False
                
        except Exception as e:
            self.logger.error(f"Sync operation failed: {e}")
            
            operation.retry_count += 1
            if operation.retry_count >= operation.max_retries:
                await self._update_operation_status(operation.id, SyncStatus.FAILED, str(e))
                self.stats.failed_operations += 1
                self.stats.pending_operations -= 1
            else:
                await self._update_operation_status(operation.id, SyncStatus.PENDING, str(e))
            
            return False
    
    async def _update_operation_status(
        self, 
        operation_id: str, 
        status: SyncStatus, 
        error_message: str = None
    ):
        """Update operation status in database."""
        try:
            with sqlite3.connect(self.db_path) as conn:
                if error_message:
                    conn.execute("""
                        UPDATE queued_operations 
                        SET status = ?, error_message = ?
                        WHERE id = ?
                    """, (status.value, error_message, operation_id))
                else:
                    conn.execute("""
                        UPDATE queued_operations 
                        SET status = ?
                        WHERE id = ?
                    """, (status.value, operation_id))
                
                conn.commit()
                
        except Exception as e:
            self.logger.error(f"Failed to update operation status: {e}")
    
    async def sync_all_pending(self) -> Dict[str, int]:
        """Synchronize all pending operations."""
        if not self.is_online:
            self.logger.warning("Cannot sync while offline")
            return {"synced": 0, "failed": 0}
        
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.execute("""
                    SELECT * FROM queued_operations 
                    WHERE status = 'pending' 
                    ORDER BY created_at ASC
                """)
                
                operations = []
                for row in cursor:
                    op_dict = {
                        'id': row[0],
                        'operation_type': row[1],
                        'resource_type': row[2],
                        'resource_id': row[3],
                        'data': row[4],
                        'created_at': row[5],
                        'retry_count': row[6],
                        'max_retries': row[7],
                        'status': row[8],
                        'error_message': row[9]
                    }
                    operations.append(QueuedOperation.from_dict(op_dict))
            
            synced = 0
            failed = 0
            
            for operation in operations:
                success = await self._sync_single_operation(operation)
                if success:
                    synced += 1
                else:
                    failed += 1
            
            self.stats.last_sync_time = datetime.now()
            self._save_stats()
            
            self.logger.info(f"Sync completed: {synced} synced, {failed} failed")
            
            return {"synced": synced, "failed": failed}
            
        except Exception as e:
            self.logger.error(f"Sync all pending failed: {e}")
            return {"synced": 0, "failed": 0}
    
    async def set_online_status(self, is_online: bool):
        """Set online/offline status."""
        old_status = self.is_online
        self.is_online = is_online
        self.stats.is_online = is_online
        
        if old_status != is_online:
            if is_online:
                self.logger.info("Going online - starting sync")
                asyncio.create_task(self.sync_all_pending())
            else:
                self.logger.info("Going offline - operations will be queued")
            
            self._save_stats()
    
    async def get_pending_operations(self, resource_type: str = None) -> List[QueuedOperation]:
        """Get pending operations, optionally filtered by resource type."""
        try:
            with sqlite3.connect(self.db_path) as conn:
                if resource_type:
                    cursor = conn.execute("""
                        SELECT * FROM queued_operations 
                        WHERE status = 'pending' AND resource_type = ?
                        ORDER BY created_at ASC
                    """, (resource_type,))
                else:
                    cursor = conn.execute("""
                        SELECT * FROM queued_operations 
                        WHERE status = 'pending'
                        ORDER BY created_at ASC
                    """)
                
                operations = []
                for row in cursor:
                    op_dict = {
                        'id': row[0],
                        'operation_type': row[1],
                        'resource_type': row[2],
                        'resource_id': row[3],
                        'data': row[4],
                        'created_at': row[5],
                        'retry_count': row[6],
                        'max_retries': row[7],
                        'status': row[8],
                        'error_message': row[9]
                    }
                    operations.append(QueuedOperation.from_dict(op_dict))
                
                return operations
                
        except Exception as e:
            self.logger.error(f"Failed to get pending operations: {e}")
            return []
    
    async def clear_completed_operations(self, older_than_days: int = 7) -> int:
        """Clear completed operations older than specified days."""
        try:
            cutoff_time = time.time() - (older_than_days * 24 * 3600)
            
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.execute("""
                    SELECT COUNT(*) FROM queued_operations 
                    WHERE status IN ('completed', 'failed') AND created_at < ?
                """, (cutoff_time,))
                
                count = cursor.fetchone()[0]
                
                conn.execute("""
                    DELETE FROM queued_operations 
                    WHERE status IN ('completed', 'failed') AND created_at < ?
                """, (cutoff_time,))
                
                conn.commit()
                
                self.logger.info(f"Cleared {count} old operations")
                return count
                
        except Exception as e:
            self.logger.error(f"Failed to clear completed operations: {e}")
            return 0
    
    async def get_stats(self) -> SyncStats:
        """Get synchronization statistics."""
        return self.stats
    
    def _start_sync_task(self):
        """Start background synchronization task."""
        async def sync_loop():
            while True:
                try:
                    await asyncio.sleep(60)  # Check every minute
                    
                    if self.is_online and self.stats.pending_operations > 0:
                        await self.sync_all_pending()
                    
                    # Clean up old operations weekly
                    if datetime.now().hour == 2:  # 2 AM
                        await self.clear_completed_operations()
                        
                except Exception as e:
                    self.logger.error(f"Sync task error: {e}")
        
        self._sync_task = asyncio.create_task(sync_loop())
    
    async def close(self):
        """Close offline manager."""
        if self._sync_task:
            self._sync_task.cancel()
            try:
                await self._sync_task
            except asyncio.CancelledError:
                pass
        
        self._save_stats()
        self.logger.info("Offline manager closed")


# Global offline manager instance
offline_manager = OfflineManager()