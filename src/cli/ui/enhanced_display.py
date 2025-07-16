"""Enhanced display utilities with progress bars, search, and advanced UI features."""

import asyncio
import time
import sys
from typing import List, Dict, Any, Optional, Callable, Union
from dataclasses import dataclass
from enum import Enum
import click
from tabulate import tabulate

from ...core.utils import format_bytes, format_duration, truncate_string
from ...models.node import Node


class ProgressStyle(Enum):
    """Progress bar styles."""
    BAR = "bar"
    SPINNER = "spinner"
    DOTS = "dots"
    PERCENTAGE = "percentage"


@dataclass
class ProgressConfig:
    """Progress bar configuration."""
    style: ProgressStyle = ProgressStyle.BAR
    width: int = 50
    show_percentage: bool = True
    show_eta: bool = True
    show_speed: bool = False
    color: str = "green"


class ProgressBar:
    """Advanced progress bar with multiple styles."""
    
    def __init__(self, total: int, config: ProgressConfig = None):
        self.total = total
        self.current = 0
        self.config = config or ProgressConfig()
        self.start_time = time.time()
        self.last_update = 0
        self.description = ""
        
        # Spinner characters
        self.spinner_chars = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        self.spinner_index = 0
        
        # Dots animation
        self.dots_count = 0
        self.max_dots = 3
    
    def update(self, increment: int = 1, description: str = None):
        """Update progress bar."""
        self.current = min(self.current + increment, self.total)
        if description:
            self.description = description
        
        # Throttle updates to avoid flickering
        current_time = time.time()
        if current_time - self.last_update < 0.1 and self.current < self.total:
            return
        
        self.last_update = current_time
        self._render()
    
    def set_progress(self, current: int, description: str = None):
        """Set absolute progress."""
        self.current = min(max(current, 0), self.total)
        if description:
            self.description = description
        self._render()
    
    def _render(self):
        """Render progress bar."""
        if self.config.style == ProgressStyle.BAR:
            self._render_bar()
        elif self.config.style == ProgressStyle.SPINNER:
            self._render_spinner()
        elif self.config.style == ProgressStyle.DOTS:
            self._render_dots()
        elif self.config.style == ProgressStyle.PERCENTAGE:
            self._render_percentage()
    
    def _render_bar(self):
        """Render bar-style progress."""
        percentage = (self.current / self.total) * 100 if self.total > 0 else 0
        filled_width = int((self.current / self.total) * self.config.width) if self.total > 0 else 0
        
        # Create bar
        filled = "█" * filled_width
        empty = "░" * (self.config.width - filled_width)
        bar = f"|{filled}{empty}|"
        
        # Add percentage
        percentage_str = f" {percentage:5.1f}%" if self.config.show_percentage else ""
        
        # Add ETA
        eta_str = ""
        if self.config.show_eta and self.current > 0:
            elapsed = time.time() - self.start_time
            if self.current < self.total:
                eta = (elapsed / self.current) * (self.total - self.current)
                eta_str = f" ETA: {format_duration(int(eta))}"
        
        # Add speed
        speed_str = ""
        if self.config.show_speed and self.current > 0:
            elapsed = time.time() - self.start_time
            speed = self.current / elapsed
            speed_str = f" ({speed:.1f}/s)"
        
        # Combine all parts
        progress_line = f"\r{self.description} {bar}{percentage_str}{eta_str}{speed_str} ({self.current}/{self.total})"
        
        # Color the output
        if self.config.color:
            progress_line = click.style(progress_line, fg=self.config.color)
        
        click.echo(progress_line, nl=False)
        
        if self.current >= self.total:
            click.echo()  # New line when complete
    
    def _render_spinner(self):
        """Render spinner-style progress."""
        self.spinner_index = (self.spinner_index + 1) % len(self.spinner_chars)
        spinner = self.spinner_chars[self.spinner_index]
        
        percentage = (self.current / self.total) * 100 if self.total > 0 else 0
        progress_line = f"\r{spinner} {self.description} {percentage:5.1f}% ({self.current}/{self.total})"
        
        if self.config.color:
            progress_line = click.style(progress_line, fg=self.config.color)
        
        click.echo(progress_line, nl=False)
        
        if self.current >= self.total:
            click.echo()
    
    def _render_dots(self):
        """Render dots-style progress."""
        self.dots_count = (self.dots_count + 1) % (self.max_dots + 1)
        dots = "." * self.dots_count + " " * (self.max_dots - self.dots_count)
        
        percentage = (self.current / self.total) * 100 if self.total > 0 else 0
        progress_line = f"\r{self.description}{dots} {percentage:5.1f}% ({self.current}/{self.total})"
        
        if self.config.color:
            progress_line = click.style(progress_line, fg=self.config.color)
        
        click.echo(progress_line, nl=False)
        
        if self.current >= self.total:
            click.echo()
    
    def _render_percentage(self):
        """Render percentage-only progress."""
        percentage = (self.current / self.total) * 100 if self.total > 0 else 0
        progress_line = f"\r{self.description} {percentage:5.1f}% ({self.current}/{self.total})"
        
        if self.config.color:
            progress_line = click.style(progress_line, fg=self.config.color)
        
        click.echo(progress_line, nl=False)
        
        if self.current >= self.total:
            click.echo()
    
    def finish(self, message: str = "Complete!"):
        """Finish progress bar with message."""
        self.current = self.total
        self._render()
        click.echo(f" {message}")


class SearchFilter:
    """Advanced search and filter functionality."""
    
    def __init__(self):
        self.filters = {}
        self.search_term = ""
        self.sort_field = None
        self.sort_reverse = False
    
    def set_search_term(self, term: str):
        """Set search term."""
        self.search_term = term.lower().strip()
    
    def add_filter(self, field: str, value: Any, operator: str = "eq"):
        """Add filter condition."""
        self.filters[field] = {"value": value, "operator": operator}
    
    def set_sort(self, field: str, reverse: bool = False):
        """Set sorting field and direction."""
        self.sort_field = field
        self.sort_reverse = reverse
    
    def apply_to_nodes(self, nodes: List[Node]) -> List[Node]:
        """Apply search and filters to node list."""
        filtered_nodes = nodes.copy()
        
        # Apply search term
        if self.search_term:
            filtered_nodes = [
                node for node in filtered_nodes
                if (self.search_term in node.name.lower() or
                    self.search_term in node.address.lower() or
                    self.search_term in str(node.port) or
                    self.search_term in node.status.value.lower())
            ]
        
        # Apply filters
        for field, filter_config in self.filters.items():
            value = filter_config["value"]
            operator = filter_config["operator"]
            
            if operator == "eq":
                filtered_nodes = [node for node in filtered_nodes if getattr(node, field, None) == value]
            elif operator == "ne":
                filtered_nodes = [node for node in filtered_nodes if getattr(node, field, None) != value]
            elif operator == "gt":
                filtered_nodes = [node for node in filtered_nodes if getattr(node, field, 0) > value]
            elif operator == "lt":
                filtered_nodes = [node for node in filtered_nodes if getattr(node, field, 0) < value]
            elif operator == "contains":
                filtered_nodes = [
                    node for node in filtered_nodes 
                    if value.lower() in str(getattr(node, field, "")).lower()
                ]
        
        # Apply sorting
        if self.sort_field:
            try:
                filtered_nodes.sort(
                    key=lambda x: getattr(x, self.sort_field, ""),
                    reverse=self.sort_reverse
                )
            except Exception:
                pass  # Ignore sorting errors
        
        return filtered_nodes


class EnhancedTable:
    """Enhanced table display with pagination, sorting, and filtering."""
    
    def __init__(self, data: List[Dict[str, Any]], headers: List[str]):
        self.data = data
        self.headers = headers
        self.page_size = 20
        self.current_page = 0
        self.search_filter = SearchFilter()
        
    def set_page_size(self, size: int):
        """Set page size for pagination."""
        self.page_size = max(1, size)
        self.current_page = 0
    
    def next_page(self) -> bool:
        """Go to next page."""
        filtered_data = self._apply_filters()
        max_pages = (len(filtered_data) - 1) // self.page_size + 1
        
        if self.current_page < max_pages - 1:
            self.current_page += 1
            return True
        return False
    
    def prev_page(self) -> bool:
        """Go to previous page."""
        if self.current_page > 0:
            self.current_page -= 1
            return True
        return False
    
    def _apply_filters(self) -> List[Dict[str, Any]]:
        """Apply search and filters to data."""
        filtered_data = self.data.copy()
        
        # Apply search term
        if self.search_filter.search_term:
            filtered_data = [
                row for row in filtered_data
                if any(self.search_filter.search_term in str(value).lower() 
                      for value in row.values())
            ]
        
        # Apply sorting
        if self.search_filter.sort_field and self.search_filter.sort_field in self.headers:
            try:
                filtered_data.sort(
                    key=lambda x: x.get(self.search_filter.sort_field, ""),
                    reverse=self.search_filter.sort_reverse
                )
            except Exception:
                pass
        
        return filtered_data
    
    def display(self):
        """Display current page of table."""
        filtered_data = self._apply_filters()
        
        # Calculate pagination
        total_items = len(filtered_data)
        max_pages = (total_items - 1) // self.page_size + 1 if total_items > 0 else 1
        start_idx = self.current_page * self.page_size
        end_idx = min(start_idx + self.page_size, total_items)
        
        page_data = filtered_data[start_idx:end_idx]
        
        # Display table
        if page_data:
            # Prepare table data
            table_data = []
            for row in page_data:
                table_row = [row.get(header, "") for header in self.headers]
                table_data.append(table_row)
            
            click.echo(tabulate(table_data, headers=self.headers, tablefmt="grid"))
        else:
            click.echo("No data to display")
        
        # Display pagination info
        if total_items > self.page_size:
            click.echo(f"\nPage {self.current_page + 1} of {max_pages} "
                      f"(showing {start_idx + 1}-{end_idx} of {total_items} items)")
        
        # Display search/filter info
        if self.search_filter.search_term:
            click.echo(f"Search: '{self.search_filter.search_term}'")
        
        if self.search_filter.sort_field:
            direction = "↓" if self.search_filter.sort_reverse else "↑"
            click.echo(f"Sort: {self.search_filter.sort_field} {direction}")


class BulkOperationManager:
    """Manager for bulk operations with progress tracking."""
    
    def __init__(self):
        self.selected_items = set()
        self.operations = {}
    
    def select_item(self, item_id: str):
        """Select an item for bulk operations."""
        self.selected_items.add(item_id)
    
    def deselect_item(self, item_id: str):
        """Deselect an item."""
        self.selected_items.discard(item_id)
    
    def select_all(self, item_ids: List[str]):
        """Select all items."""
        self.selected_items.update(item_ids)
    
    def clear_selection(self):
        """Clear all selections."""
        self.selected_items.clear()
    
    def get_selected_count(self) -> int:
        """Get number of selected items."""
        return len(self.selected_items)
    
    async def execute_bulk_operation(
        self,
        operation_name: str,
        operation_func: Callable,
        items: List[Any],
        progress_callback: Optional[Callable] = None
    ) -> Dict[str, Any]:
        """Execute bulk operation with progress tracking."""
        if not self.selected_items:
            return {"success": 0, "failed": 0, "errors": []}
        
        # Filter items to selected ones
        selected_items = [item for item in items if str(getattr(item, 'id', '')) in self.selected_items]
        
        if not selected_items:
            return {"success": 0, "failed": 0, "errors": ["No valid items selected"]}
        
        # Initialize progress
        total_items = len(selected_items)
        progress_config = ProgressConfig(style=ProgressStyle.BAR, show_eta=True)
        progress = ProgressBar(total_items, progress_config)
        
        results = {"success": 0, "failed": 0, "errors": []}
        
        click.echo(f"\nExecuting {operation_name} on {total_items} items...")
        
        for i, item in enumerate(selected_items):
            try:
                # Update progress
                progress.update(0, f"Processing {getattr(item, 'name', f'item {i+1}')}...")
                
                # Execute operation
                success = await operation_func(item)
                
                if success:
                    results["success"] += 1
                else:
                    results["failed"] += 1
                    results["errors"].append(f"Operation failed for {getattr(item, 'name', f'item {i+1}')}")
                
                # Update progress
                progress.update(1)
                
                # Call progress callback if provided
                if progress_callback:
                    await progress_callback(i + 1, total_items, results)
                
                # Small delay to avoid overwhelming the API
                await asyncio.sleep(0.1)
                
            except Exception as e:
                results["failed"] += 1
                results["errors"].append(f"Error processing {getattr(item, 'name', f'item {i+1}')}: {e}")
                progress.update(1)
        
        progress.finish(f"Completed! {results['success']} successful, {results['failed']} failed")
        
        return results


class InteractiveMenu:
    """Enhanced interactive menu with keyboard shortcuts and search."""
    
    def __init__(self, title: str, options: List[Dict[str, Any]]):
        self.title = title
        self.options = options
        self.selected_index = 0
        self.search_mode = False
        self.search_term = ""
        self.filtered_options = options.copy()
    
    def _filter_options(self):
        """Filter options based on search term."""
        if not self.search_term:
            self.filtered_options = self.options.copy()
        else:
            self.filtered_options = [
                opt for opt in self.options
                if self.search_term.lower() in opt.get("title", "").lower() or
                   self.search_term.lower() in opt.get("description", "").lower()
            ]
        
        # Reset selection if needed
        if self.selected_index >= len(self.filtered_options):
            self.selected_index = max(0, len(self.filtered_options) - 1)
    
    def display(self):
        """Display the interactive menu."""
        click.clear()
        
        # Display title
        click.echo("=" * 80)
        click.echo(f"{self.title:^80}")
        click.echo("=" * 80)
        
        # Display search bar if in search mode
        if self.search_mode:
            click.echo(f"Search: {self.search_term}_")
            click.echo("-" * 80)
        
        # Display options
        for i, option in enumerate(self.filtered_options):
            prefix = "→ " if i == self.selected_index else "  "
            title = option.get("title", f"Option {i+1}")
            
            if option.get("disabled", False):
                title = click.style(title, fg="bright_black")
            elif i == self.selected_index:
                title = click.style(title, fg="bright_green", bold=True)
            
            click.echo(f"{prefix}{option.get('key', str(i+1)):>2}. {title}")
            
            # Show description if available
            if option.get("description") and i == self.selected_index:
                desc = click.style(f"     {option['description']}", fg="bright_black")
                click.echo(desc)
        
        click.echo("=" * 80)
        
        # Display help
        help_text = "↑/↓: Navigate | Enter: Select | /: Search | q: Quit"
        if self.search_mode:
            help_text = "Type to search | Esc: Exit search | Enter: Select"
        
        click.echo(click.style(help_text, fg="bright_blue"))
    
    async def run(self) -> Optional[Dict[str, Any]]:
        """Run the interactive menu."""
        while True:
            self.display()
            
            try:
                # Get user input (simplified for demo)
                choice = click.prompt("Choice", default="", show_default=False)
                
                if choice.lower() == 'q':
                    return None
                elif choice == '/':
                    self.search_mode = True
                    self.search_term = click.prompt("Search", default="")
                    self._filter_options()
                    self.search_mode = False
                elif choice.isdigit():
                    index = int(choice) - 1
                    if 0 <= index < len(self.filtered_options):
                        return self.filtered_options[index]
                elif choice == "":
                    if self.filtered_options:
                        return self.filtered_options[self.selected_index]
                
            except (KeyboardInterrupt, EOFError):
                return None


# Enhanced display functions
def display_nodes_enhanced(
    nodes: List[Node],
    search_term: str = "",
    sort_field: str = None,
    sort_reverse: bool = False,
    page_size: int = 20
):
    """Display nodes with enhanced features."""
    if not nodes:
        click.echo("No nodes found")
        return
    
    # Prepare data for enhanced table
    headers = ["ID", "Name", "Address", "Port", "API Port", "Status", "Version", "Coefficient"]
    data = []
    
    for node in nodes:
        data.append({
            "ID": node.id,
            "Name": truncate_string(node.name, 20),
            "Address": node.address,
            "Port": node.port,
            "API Port": node.api_port,
            "Status": node.display_status,
            "Version": node.xray_version or "N/A",
            "Coefficient": f"{node.usage_coefficient:.1f}"
        })
    
    # Create enhanced table
    table = EnhancedTable(data, headers)
    table.set_page_size(page_size)
    
    # Apply search and sort
    if search_term:
        table.search_filter.set_search_term(search_term)
    
    if sort_field:
        table.search_filter.set_sort(sort_field, sort_reverse)
    
    # Display table
    click.echo("\n" + "="*80)
    click.echo(f"NODES ({len(nodes)} total)")
    click.echo("="*80)
    
    table.display()
    
    # Interactive navigation
    while True:
        click.echo("\nNavigation: [n]ext page | [p]revious page | [s]earch | [q]uit")
        choice = click.prompt("Choice", default="q").lower()
        
        if choice == 'n':
            if not table.next_page():
                click.echo("Already on last page")
            else:
                table.display()
        elif choice == 'p':
            if not table.prev_page():
                click.echo("Already on first page")
            else:
                table.display()
        elif choice == 's':
            search = click.prompt("Search term", default="")
            table.search_filter.set_search_term(search)
            table.current_page = 0
            table.display()
        elif choice == 'q':
            break


async def progress_demo():
    """Demo of progress bar functionality."""
    click.echo("Progress Bar Demo:")
    
    # Bar style
    progress = ProgressBar(100, ProgressConfig(style=ProgressStyle.BAR, show_eta=True))
    for i in range(101):
        progress.update(1, f"Processing item {i}")
        await asyncio.sleep(0.05)
    
    # Spinner style
    progress = ProgressBar(50, ProgressConfig(style=ProgressStyle.SPINNER))
    for i in range(51):
        progress.update(1, f"Loading data {i}")
        await asyncio.sleep(0.1)


# Global instances
bulk_manager = BulkOperationManager()
search_filter = SearchFilter()