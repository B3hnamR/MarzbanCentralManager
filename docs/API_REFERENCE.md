# API Reference

## Node Management APIs

Based on the Marzban API documentation, the following endpoints are available for node management:

### Authentication
All API calls require authentication using Bearer token obtained from `/api/admin/token`.

### Node Settings
- **GET** `/api/node/settings` - Retrieve node settings including TLS certificate

### Node Management
- **GET** `/api/nodes` - List all nodes
- **POST** `/api/node` - Create new node
- **GET** `/api/node/{node_id}` - Get specific node
- **PUT** `/api/node/{node_id}` - Update node
- **DELETE** `/api/node/{node_id}` - Delete node
- **POST** `/api/node/{node_id}/reconnect` - Reconnect node

### Usage Statistics
- **GET** `/api/nodes/usage` - Get usage statistics for nodes

## Data Models

### Node Model
```json
{
  "id": 1,
  "name": "Node Name",
  "address": "192.168.1.1",
  "port": 62050,
  "api_port": 62051,
  "usage_coefficient": 1.0,
  "status": "connected",
  "xray_version": "1.8.1",
  "message": null
}
```

### Node Creation
```json
{
  "name": "Node Name",
  "address": "192.168.1.1",
  "port": 62050,
  "api_port": 62051,
  "usage_coefficient": 1.0,
  "add_as_new_host": true
}
```

### Usage Statistics
```json
{
  "usages": [
    {
      "node_id": 1,
      "node_name": "Node Name",
      "uplink": 1000000,
      "downlink": 2000000
    }
  ]
}
```

## Status Codes

- **200** - Success
- **401** - Unauthorized (invalid token)
- **403** - Forbidden (insufficient permissions)
- **404** - Not Found
- **409** - Conflict (entity already exists)
- **422** - Validation Error