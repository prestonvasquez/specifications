# CMAP Specification - UML Breakdown

This document provides a series of UML diagrams to visualize different aspects of the Connection Monitoring and Pooling (CMAP) specification.

## 1. Class Diagram - Core Components

```mermaid
classDiagram
    class ConnectionPool {
        +WaitQueue waitQueue
        +int generation
        +Map~ObjectId, Tuple~ serviceGenerations
        +string state
        +int totalConnectionCount
        +int availableConnectionCount  
        +int pendingConnectionCount
        +Connection checkOut()
        +void checkIn(Connection)
        +void clear(boolean interruptInUse)
        +void ready()
        +void close()
    }

    class Connection {
        +int id
        +string address
        +int generation
        +string state
        +Socket socket
    }

    class WaitQueue {
        +boolean isThreadSafe
        +boolean isOrdered
        +void enter(Thread)
        +void leave(Thread)
        +Connection waitForConnection(timeout)
    }

    class ConnectionPoolOptions {
        +int maxPoolSize
        +int minPoolSize
        +int maxIdleTimeMS
        +int maxConnecting
        +int waitQueueTimeoutMS
    }

    ConnectionPool "1" --> "many" Connection : manages
    ConnectionPool "1" --> "1" WaitQueue : has
    ConnectionPool --> ConnectionPoolOptions : configuredWith
    
    note for Connection "States: pending → available → in use → closed"
    note for ConnectionPool "States: paused → ready → closed"
```

## 2. State Diagram - Connection Lifecycle

```mermaid
stateDiagram-v2
    [*] --> pending : create()
    
    pending --> available : establish()
    pending --> closed : establish() fails
    
    available --> inUse : checkOut()
    available --> closed : perish or pool.close()
    
    inUse --> available : checkIn() (healthy)
    inUse --> closed : checkIn() (perished) or error
    
    closed --> [*]
    
    note right of pending : TCP connection not yet established
    note right of available : Ready to be checked out
    note right of inUse : Serving an operation
    note right of closed : Socket closed, unusable
```

## 3. State Diagram - Pool Lifecycle

```mermaid
stateDiagram-v2
    [*] --> paused : create()
    
    paused --> ready : ready()
    paused --> closed : close()
    
    ready --> paused : clear()
    ready --> closed : close()
    
    closed --> [*]
    
    note right of paused : No checkouts allowed\nNo background activity
    note right of ready : Normal operations\nBackground maintenance active
    note right of closed : Permanent shutdown\nAll operations fail
```

## 4. Sequence Diagram - Successful CheckOut Flow

```mermaid
sequenceDiagram
    participant App as Application
    participant Driver as Driver
    participant Pool as ConnectionPool
    participant WQ as WaitQueue
    participant Conn as Connection

    App->>Driver: request operation
    Driver->>Pool: checkOut()
    
    Pool->>Pool: emit ConnectionCheckOutStartedEvent
    Pool->>WQ: enter queue
    
    alt Available connection exists
        Pool->>Pool: find available connection
        Pool->>Pool: check if perished
        alt Connection is healthy
            Pool->>Pool: mark as "in use"
            Pool->>Pool: emit ConnectionCheckedOutEvent
            Pool->>Driver: return connection
        else Connection is perished  
            Pool->>Pool: close perished connection
            Pool->>Pool: continue search
        end
    else No available connections
        alt Pool not at maxPoolSize
            Pool->>Conn: create()
            Pool->>Pool: emit ConnectionCreatedEvent
            Pool->>Conn: establish()
            Pool->>Pool: emit ConnectionReadyEvent
            Pool->>Pool: mark as "in use"
            Pool->>Pool: emit ConnectionCheckedOutEvent
            Pool->>Driver: return connection
        else Pool at maxPoolSize
            Pool->>WQ: wait for availability or timeout
        end
    end
    
    WQ->>Pool: leave queue
    Driver->>App: proceed with operation
```

## 5. Sequence Diagram - Pool Clear Operation

```mermaid
sequenceDiagram
    participant SDAM as SDAM Monitor
    participant Pool as ConnectionPool
    participant WQ as WaitQueue
    participant BG as BackgroundThread
    participant Conns as In-Use Connections

    SDAM->>Pool: clear(interruptInUseConnections=true)
    
    Pool->>Pool: increment generation
    Pool->>Pool: set state to "paused"
    
    Pool->>WQ: clear all waiting requests
    WQ-->>WQ: fail all requests with PoolClearedError
    
    Pool->>Pool: emit PoolClearedEvent
    
    alt interruptInUseConnections is true
        Pool->>BG: schedule immediate run
        BG->>Conns: interrupt connections with old generation
        Conns-->>Conns: fail operations with retryable error
    end
    
    note over Pool: Pool now in "paused" state
    note over Pool: Awaiting ready() call from SDAM
```

## 6. Activity Diagram - Connection Establishment Process

```mermaid
flowchart TD
    A[Create Connection] --> B[Set state to 'pending']
    B --> C[Emit ConnectionCreatedEvent]
    C --> D[Establish TCP Socket]
    
    D --> E{TCP Success?}
    E -->|No| F[Close Connection]
    E -->|Yes| G[Perform MongoDB Handshake]
    
    G --> H{Handshake Success?}
    H -->|No| F
    H -->|Yes| I[Handle OP_COMPRESSED]
    
    I --> J[Perform Authentication]
    J --> K{Auth Success?}
    K -->|No| F
    K -->|Yes| L[Set state to 'available']
    
    L --> M[Emit ConnectionReadyEvent]
    M --> N[Add to available connections]
    
    F --> O[Emit ConnectionClosedEvent]
    F --> P[Decrement counters]
    
    style A fill:#e1f5fe
    style N fill:#c8e6c9
    style O fill:#ffcdd2
```

## 7. Component Diagram - System Integration

```mermaid
graph TB
    subgraph "Application Layer"
        APP[Application Code]
    end
    
    subgraph "Driver Layer"
        CRUD[CRUD Operations]
        SDAM[Server Discovery & Monitoring]
        SS[Server Selection]
    end
    
    subgraph "CMAP Layer"
        POOL[Connection Pool]
        WQ[Wait Queue]
        CONN[Connections]
        EVENTS[Pool Events]
    end
    
    subgraph "Network Layer"
        TCP[TCP Sockets]
        TLS[TLS Layer]
        MONGO[MongoDB Protocol]
    end
    
    APP --> CRUD
    CRUD --> SS
    SS --> POOL
    SDAM --> POOL
    
    POOL --> WQ
    POOL --> CONN
    POOL --> EVENTS
    
    CONN --> TCP
    TCP --> TLS
    TLS --> MONGO
    
    EVENTS -.-> APP
```

## 8. Timing Diagram - Concurrent Operations

```mermaid
gantt
    title Connection Pool Timeline
    dateFormat X
    axisFormat %L ms
    
    section Thread 1
    CheckOut Request    :active, t1_req, 0, 50
    Wait in Queue      :t1_wait, 50, 150
    Use Connection     :active, t1_use, 150, 300
    CheckIn           :milestone, t1_in, 300
    
    section Thread 2
    CheckOut Request    :active, t2_req, 100, 125
    Wait in Queue      :t2_wait, 125, 300
    Use Connection     :active, t2_use, 300, 450
    CheckIn           :milestone, t2_in, 450
    
    section Pool State
    Available Conn: 1   :done, pool1, 0, 150
    Available Conn: 0   :crit, pool2, 150, 300
    Available Conn: 1   :done, pool3, 300, 450
    
    section Background
    Maintain minPoolSize :bg1, 0, 500
```

## Key Insights from UML Analysis

### 1. **State Management Complexity**
The state diagrams reveal that both connections and pools have well-defined state machines, but the interaction between them creates complexity in edge cases.

### 2. **Event-Driven Architecture**
The sequence diagrams show heavy use of events, making the system observable but potentially creating performance considerations.

### 3. **Concurrency Challenges**
The timing diagram illustrates how multiple threads compete for limited resources, highlighting the importance of fair queuing.

### 4. **Layered Responsibility**
The component diagram shows clear separation of concerns, with CMAP focusing purely on connection lifecycle management.

### 5. **Error Propagation Paths**
Multiple diagrams show various failure points and how errors propagate through the system, emphasizing the need for robust error handling.

## Usage Notes

- These diagrams are complementary - each captures a different aspect of the system
- The state diagrams are particularly important for understanding valid transitions
- The sequence diagrams help understand the temporal aspects and event ordering
- The component diagram shows integration points with other MongoDB specifications
