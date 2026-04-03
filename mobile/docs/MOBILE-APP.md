# XDC Node Monitor - Mobile App Design Document

## Overview

The XDC Node Monitor is a companion mobile application for XDC Network node operators. It provides real-time monitoring, alerting, and basic management capabilities for XDC nodes managed through the SkyNet infrastructure.

## Target Platforms

- **iOS** 14.0+ (iPhone, iPad)
- **Android** 8.0+ (API level 26+)

## Technology Stack

| Component | Technology |
|-----------|------------|
| Framework | React Native + Expo |
| Navigation | Expo Router |
| State Management | Zustand |
| Data Fetching | TanStack Query (React Query) |
| Styling | React Native StyleSheet |
| Authentication | expo-local-authentication |
| Push Notifications | expo-notifications |
| Secure Storage | expo-secure-store |

---

## Core Features

### 1. Dashboard

**Purpose:** Provide at-a-glance overview of all monitored nodes.

**Components:**
- Status summary cards (total, online, syncing, offline)
- Network statistics (latest block, peer count, avg sync time)
- Quick action buttons
- Alert count indicator

**Data Refresh:** Auto-refresh every 30s (configurable)

### 2. Node List

**Purpose:** View and access all configured nodes.

**Features:**
- List view with status indicators
- Search and filter by network/status
- Sync progress bars for syncing nodes
- Pull-to-refresh
- Tap to view details

### 3. Node Detail

**Purpose:** Deep dive into individual node status and management.

**Information Displayed:**
- Current status with uptime
- Block height and sync progress
- Peer count and list
- Resource usage (CPU, memory, disk)
- Node configuration details
- Recent log preview

**Quick Actions:**
- Restart node
- Add/remove peers
- View full logs

### 4. Alerts

**Purpose:** Centralized alert management.

**Features:**
- Real-time alert display
- Severity indicators (critical, warning, info)
- Dismiss individual or all alerts
- Actionable alerts with quick actions
- Historical alert view

**Alert Types:**
- Node offline
- Sync stalled
- Low peer count
- High resource usage
- Masternode issues
- Version outdated

### 5. Settings

**Purpose:** Configure app behavior and security.

**Options:**
- API endpoint configuration
- Push notification preferences
- Biometric authentication toggle
- Refresh interval
- Theme selection
- Quiet hours

---

## Push Notifications

### Implementation

Using `expo-notifications` with Firebase Cloud Messaging (Android) and Apple Push Notification Service (iOS).

### Notification Types

| Type | Priority | Vibration | Sound |
|------|----------|-----------|-------|
| Node Offline | Critical | Yes | Alert |
| Sync Stalled | High | Yes | Default |
| Low Peers | Medium | No | Default |
| Resource Warning | Medium | No | Silent |
| Info Updates | Low | No | Silent |

### Backend Integration

```typescript
// Register push token with SkyNet API
POST /api/v1/push/register
{
  "token": "ExponentPushToken[xxx]",
  "platform": "ios" | "android",
  "preferences": {
    "critical": true,
    "warnings": true,
    "info": false
  }
}
```

### Quiet Hours

Users can configure quiet hours during which only critical alerts are delivered:
- Default: 10 PM - 8 AM local time
- Configurable start/end times
- Critical alerts bypass quiet hours

---

## Real-Time Sync Status

### Polling Strategy

```typescript
// Dashboard: 30s interval
// Node list: 30s interval
// Node detail: 15s interval (more granular)
// Alerts: 30s interval

const { data, refetch } = useQuery({
  queryKey: ['node', id],
  queryFn: () => api.getNode(id),
  refetchInterval: 15000,
});
```

### WebSocket Support (Future)

For real-time updates without polling:

```typescript
// Connect to SkyNet WebSocket
const ws = new WebSocket('wss://api.skyskynet.xdcindia.com/ws');

ws.onmessage = (event) => {
  const update = JSON.parse(event.data);
  queryClient.setQueryData(['node', update.nodeId], update);
};
```

---

## Quick Actions

### Restart Node

```typescript
// User flow:
// 1. Tap "Restart" button
// 2. Confirmation dialog
// 3. API call with loading state
// 4. Success/error feedback
// 5. Refresh node data

const restartMutation = useMutation({
  mutationFn: () => api.restartNode(nodeId),
  onSuccess: () => {
    Alert.alert('Success', 'Node restart initiated');
    queryClient.invalidateQueries(['node', nodeId]);
  },
});
```

### Add Peer

```typescript
// User flow:
// 1. Tap "Add Peer" button
// 2. Prompt for enode URL
// 3. Validate format
// 4. API call
// 5. Update peer list

const addPeerMutation = useMutation({
  mutationFn: (enode: string) => api.addPeer(nodeId, enode),
});
```

### Supported Actions

| Action | Availability | Confirmation Required |
|--------|--------------|----------------------|
| Restart | All nodes | Yes |
| Stop | All nodes | Yes |
| Start | Stopped only | No |
| Add Peer | All nodes | No |
| Remove Peer | All nodes | Yes |
| Update | Outdated only | Yes |

---

## Biometric Authentication

### Implementation

Using `expo-local-authentication`:

```typescript
import * as LocalAuthentication from 'expo-local-authentication';

const authenticate = async () => {
  const hasHardware = await LocalAuthentication.hasHardwareAsync();
  const isEnrolled = await LocalAuthentication.isEnrolledAsync();

  if (hasHardware && isEnrolled) {
    const result = await LocalAuthentication.authenticateAsync({
      promptMessage: 'Authenticate to access XDC Node Monitor',
      fallbackLabel: 'Use passcode',
      cancelLabel: 'Cancel',
    });
    return result.success;
  }
  return true; // Skip if not available
};
```

### Supported Methods

- **iOS:** Face ID, Touch ID, Passcode
- **Android:** Fingerprint, Face Recognition, PIN

### Security Flow

1. App launch → Check biometric setting
2. If enabled → Prompt authentication
3. Success → Load app
4. Failure → Retry up to 3 times
5. Lockout → Require device passcode

### Secure Storage

API keys and sensitive data stored using `expo-secure-store`:

```typescript
import * as SecureStore from 'expo-secure-store';

await SecureStore.setItemAsync('api_key', apiKey);
const apiKey = await SecureStore.getItemAsync('api_key');
```

---

## Widget Support

### iOS Widgets (WidgetKit)

**Types:**
1. **Small Widget** - Single node status
2. **Medium Widget** - Summary of all nodes (count by status)
3. **Large Widget** - Top 3 nodes with details

**Implementation Notes:**
- Requires native Swift/Objective-C code
- Data shared via App Groups
- Background refresh every 15 minutes
- Deep links to specific screens

### Android Widgets

**Types:**
1. **Status Widget** - Node count overview
2. **Node Widget** - Single node status with quick action

**Implementation Notes:**
- Native Kotlin/Java implementation
- Widget update via WorkManager
- Configurable node selection
- Tap to open app

### Data Flow for Widgets

```
┌─────────────┐     ┌──────────────┐     ┌────────────┐
│  SkyNet API │────▶│  App Groups  │────▶│   Widget   │
│             │     │ (iOS) / SP   │     │            │
└─────────────┘     │ (Android)    │     └────────────┘
                    └──────────────┘
```

### Widget Configuration

Users can:
- Select which node to display (single node widgets)
- Choose refresh frequency
- Enable/disable alert badges

---

## API Endpoints

### Base URL
```
Production: https://api.skyskynet.xdcindia.com
Staging: https://staging-api.skyskynet.xdcindia.com
```

### Endpoints Used

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/dashboard` | GET | Dashboard overview |
| `/api/v1/nodes` | GET | List all nodes |
| `/api/v1/nodes/:id` | GET | Node details |
| `/api/v1/nodes/:id/restart` | POST | Restart node |
| `/api/v1/nodes/:id/peers` | POST | Add peer |
| `/api/v1/alerts` | GET | List alerts |
| `/api/v1/alerts/:id/dismiss` | POST | Dismiss alert |
| `/api/v1/push/register` | POST | Register push token |

### Error Handling

```typescript
class ApiError extends Error {
  constructor(message: string, public statusCode: number) {
    super(message);
  }
}

// Usage in UI
if (error instanceof ApiError) {
  if (error.statusCode === 401) {
    // Redirect to re-authenticate
  } else if (error.statusCode === 503) {
    // Show maintenance message
  }
}
```

---

## Offline Support

### Cached Data

- Last known node states
- Alert history
- User preferences

### Offline Indicators

- Banner showing offline status
- Grayed-out action buttons
- Last updated timestamp

### Sync on Reconnect

```typescript
// NetInfo listener
NetInfo.addEventListener(state => {
  if (state.isConnected) {
    queryClient.invalidateQueries();
  }
});
```

---

## Performance Considerations

### Memory Management

- Virtualized lists for node/alert lists
- Image caching for avatars/icons
- Query cache limits

### Battery Optimization

- Reduce refresh frequency when app backgrounded
- Batch network requests
- Efficient background task scheduling

### Network Efficiency

- Request compression
- Minimal payloads (server-side)
- Delta updates where possible

---

## Future Enhancements

### Phase 2

- [ ] Multi-account support
- [ ] Dark/Light theme
- [ ] Node grouping/folders
- [ ] Custom alert rules
- [ ] Log search and filter

### Phase 3

- [ ] WebSocket real-time updates
- [ ] Voice commands (Siri/Google Assistant)
- [ ] Apple Watch / Wear OS companion
- [ ] AR network visualization

---

## Testing Strategy

### Unit Tests

- Store logic
- API client
- Utility functions

### Integration Tests

- Navigation flows
- API integration
- State management

### E2E Tests

- Critical user flows (Detox)
- Device-specific testing

### Beta Testing

- TestFlight (iOS)
- Firebase App Distribution (Android)
- Internal testing group

---

## Release Process

1. Version bump in `app.json`
2. Update CHANGELOG
3. Build with EAS: `eas build`
4. Submit to stores
5. Monitor crash reports (Sentry)

### App Store Assets

- Screenshots for all device sizes
- App icon (1024x1024)
- Feature graphic (Android)
- Privacy policy
- Support URL

---

## Support

- **Documentation:** https://docs.xdc.network/mobile
- **Issues:** https://github.com/AnilChinchawale/xdc-node-setup/issues
- **Discord:** https://discord.xdc.network

---

*Last Updated: February 2026*
