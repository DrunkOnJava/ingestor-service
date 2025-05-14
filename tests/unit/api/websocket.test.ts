/**
 * WebSocket Module Tests
 * 
 * Tests the WebSocket functionality for real-time updates
 */
import { describe, it, expect, beforeEach, afterEach, jest } from '@jest/globals';
import http from 'http';
import { Server as WebSocketServer } from 'ws';
import { initWebSocketServer, EventType } from '../../../src/api/websocket';

// Mock WebSocket server
jest.mock('ws', () => {
  return {
    Server: jest.fn().mockImplementation(() => ({
      on: jest.fn(),
      clients: new Set([
        { readyState: 1, send: jest.fn() },
        { readyState: 1, send: jest.fn() },
        { readyState: 3, send: jest.fn() } // Closed connection
      ]),
      close: jest.fn()
    }))
  };
});

describe('WebSocket Module', () => {
  let mockServer: http.Server;
  let wsManager: any;
  
  beforeEach(() => {
    // Reset mocks
    jest.clearAllMocks();
    
    // Create HTTP server mock
    mockServer = new http.Server();
    
    // Initialize WebSocket server
    wsManager = initWebSocketServer(mockServer);
  });
  
  afterEach(() => {
    jest.resetAllMocks();
  });
  
  it('should create a WebSocket manager', () => {
    // Verify that WebSocket server was initialized
    expect(WebSocketServer).toHaveBeenCalledWith({
      server: mockServer,
      path: expect.any(String)
    });
    
    // Verify that WebSocket manager was returned
    expect(wsManager).toBeDefined();
    expect(wsManager.broadcast).toBeDefined();
    expect(wsManager.getConnections).toBeDefined();
  });
  
  it('should broadcast messages to all connected clients', () => {
    // Call broadcast method
    const eventType = EventType.CONTENT_PROCESSED;
    const data = { id: 'content123', type: 'text' };
    wsManager.broadcast(eventType, data);
    
    // Get WebSocket server instance
    const wsServer = (WebSocketServer as jest.Mock).mock.instances[0];
    
    // Verify that send was called on all open connections
    expect(wsServer.clients.size).toBe(3);
    let sendCalls = 0;
    
    for (const client of wsServer.clients) {
      if (client.readyState === 1) { // OPEN state
        expect(client.send).toHaveBeenCalledWith(
          expect.stringContaining(eventType)
        );
        sendCalls++;
      }
    }
    
    // Verify that send was called on exactly 2 clients (the open ones)
    expect(sendCalls).toBe(2);
  });
  
  it('should properly format broadcast messages', () => {
    // Call broadcast method
    const eventType = EventType.ENTITY_CREATED;
    const data = { id: 'entity123', type: 'person', name: 'John Doe' };
    wsManager.broadcast(eventType, data);
    
    // Get WebSocket server instance
    const wsServer = (WebSocketServer as jest.Mock).mock.instances[0];
    
    // Get the first client
    const firstClient = Array.from(wsServer.clients)[0];
    
    // Verify message format
    expect(firstClient.send).toHaveBeenCalledWith(
      expect.stringMatching(new RegExp(`"event":"${eventType}"`))
    );
    expect(firstClient.send).toHaveBeenCalledWith(
      expect.stringMatching(/"data":/)
    );
    expect(firstClient.send).toHaveBeenCalledWith(
      expect.stringMatching(/"timestamp":/)
    );
    
    // Parse the message to verify its structure
    const message = JSON.parse((firstClient.send as jest.Mock).mock.calls[0][0]);
    expect(message).toEqual({
      event: eventType,
      data: data,
      timestamp: expect.any(String)
    });
  });
  
  it('should return the number of connections', () => {
    // Call getConnections method
    const connections = wsManager.getConnections();
    
    // Verify connection count (only OPEN connections)
    expect(connections).toBe(2);
  });
});