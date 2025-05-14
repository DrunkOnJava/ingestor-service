/**
 * WebSocket Server
 * 
 * Provides real-time updates for content processing, batch jobs, and system events.
 */

import { Server as HttpServer } from 'http';
import { Server as WebSocketServer } from 'socket.io';
import jwt from 'jsonwebtoken';
import { Logger } from '../../core/logging/Logger';
import config from '../config';

// Logger instance
const logger = new Logger('api:websocket');

// Client tracking
interface ConnectedClient {
  id: string;
  userId?: string;
  username?: string;
  connectedAt: Date;
  rooms: string[];
}

// WS Event types
export enum EventType {
  PROCESSING_STARTED = 'processing:started',
  PROCESSING_COMPLETED = 'processing:completed',
  PROCESSING_FAILED = 'processing:failed',
  ENTITY_CREATED = 'entity:created',
  BATCH_STARTED = 'batch:started',
  BATCH_PROGRESS = 'batch:progress',
  BATCH_COMPLETED = 'batch:completed',
  BATCH_FAILED = 'batch:failed',
  BATCH_ITEM_STARTED = 'batch:item:started',
  BATCH_ITEM_COMPLETED = 'batch:item:completed',
  BATCH_ITEM_FAILED = 'batch:item:failed',
  SYSTEM_STATUS = 'system:status',
}

/**
 * WebSocket Manager class
 * Handles WebSocket connections and message broadcasting
 */
export class WebSocketManager {
  private io: WebSocketServer;
  private clients: Map<string, ConnectedClient> = new Map();
  
  /**
   * Initialize WebSocket server
   */
  constructor(server: HttpServer) {
    this.io = new WebSocketServer(server, {
      path: config.websocket.path,
      cors: {
        origin: config.cors.origin,
        methods: ['GET', 'POST'],
        credentials: true,
      },
    });
    
    this.setupAuthentication();
    this.setupConnectionHandlers();
    
    logger.info('WebSocket server initialized', {
      path: config.websocket.path,
    });
  }
  
  /**
   * Set up authentication middleware
   */
  private setupAuthentication() {
    this.io.use((socket, next) => {
      try {
        // Get token from query parameters
        const token = socket.handshake.query.token as string;
        
        if (!token) {
          logger.warn('WebSocket connection rejected: No token provided', {
            clientId: socket.id,
            ip: socket.handshake.address,
          });
          return next(new Error('Authentication required'));
        }
        
        // Verify JWT token
        const decoded = jwt.verify(token, config.jwt.secret) as any;
        
        // Store user info in socket
        socket.data.user = {
          id: decoded.id,
          username: decoded.username,
          role: decoded.role,
        };
        
        logger.debug('WebSocket client authenticated', {
          clientId: socket.id,
          userId: decoded.id,
          username: decoded.username,
        });
        
        next();
      } catch (error) {
        logger.warn('WebSocket authentication failed', {
          clientId: socket.id,
          error: (error as Error).message,
        });
        next(new Error('Invalid token'));
      }
    });
  }
  
  /**
   * Set up connection event handlers
   */
  private setupConnectionHandlers() {
    this.io.on('connection', (socket) => {
      // Get user info from socket data
      const user = socket.data.user;
      
      // Store client info
      const client: ConnectedClient = {
        id: socket.id,
        userId: user?.id,
        username: user?.username,
        connectedAt: new Date(),
        rooms: [],
      };
      
      this.clients.set(socket.id, client);
      
      logger.info('WebSocket client connected', {
        clientId: socket.id,
        userId: user?.id,
        username: user?.username,
      });
      
      // Join user-specific room
      if (user?.id) {
        socket.join(`user:${user.id}`);
        client.rooms.push(`user:${user.id}`);
      }
      
      // Join role-based room
      if (user?.role) {
        socket.join(`role:${user.role}`);
        client.rooms.push(`role:${user.role}`);
      }
      
      // Handle room joining
      socket.on('join', (room) => {
        // Only allow joining specific room types
        if (room.startsWith('content:') || room.startsWith('batch:') || room === 'system') {
          socket.join(room);
          client.rooms.push(room);
          
          logger.debug('Client joined room', {
            clientId: socket.id,
            room,
          });
        }
      });
      
      // Handle room leaving
      socket.on('leave', (room) => {
        socket.leave(room);
        client.rooms = client.rooms.filter(r => r !== room);
        
        logger.debug('Client left room', {
          clientId: socket.id,
          room,
        });
      });
      
      // Handle disconnect
      socket.on('disconnect', () => {
        this.clients.delete(socket.id);
        
        logger.info('WebSocket client disconnected', {
          clientId: socket.id,
          userId: user?.id,
          username: user?.username,
        });
      });
    });
    
    // Set up ping interval to keep connections alive
    setInterval(() => {
      this.io.emit('ping', { timestamp: new Date().toISOString() });
    }, config.websocket.pingInterval);
  }
  
  /**
   * Broadcast event to all connected clients or to specific room
   */
  public broadcast(event: EventType, data: any, room?: string) {
    const message = {
      event,
      data,
      timestamp: new Date().toISOString(),
    };
    
    if (room) {
      this.io.to(room).emit('event', message);
      
      logger.debug('Broadcasting to room', {
        event,
        room,
        recipients: this.io.sockets.adapter.rooms.get(room)?.size || 0,
      });
    } else {
      this.io.emit('event', message);
      
      logger.debug('Broadcasting to all clients', {
        event,
        recipients: this.clients.size,
      });
    }
  }
  
  /**
   * Send event to a specific user
   */
  public sendToUser(userId: string, event: EventType, data: any) {
    const room = `user:${userId}`;
    this.broadcast(event, data, room);
  }
  
  /**
   * Send event to users with a specific role
   */
  public sendToRole(role: string, event: EventType, data: any) {
    const room = `role:${role}`;
    this.broadcast(event, data, room);
  }
  
  /**
   * Get connected clients count
   */
  public getClientsCount(): number {
    return this.clients.size;
  }
  
  /**
   * Get connected clients info
   */
  public getClientsInfo(): ConnectedClient[] {
    return Array.from(this.clients.values());
  }
}

// Export singleton instance creator
let wsManagerInstance: WebSocketManager | null = null;

export function initWebSocketServer(server: HttpServer): WebSocketManager {
  if (!wsManagerInstance) {
    wsManagerInstance = new WebSocketManager(server);
  }
  return wsManagerInstance;
}

export function getWebSocketManager(): WebSocketManager | null {
  return wsManagerInstance;
}