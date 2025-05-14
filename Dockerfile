# Build stage
FROM node:18-alpine AS build

WORKDIR /app

# Copy package.json and package-lock.json
COPY package*.json ./

# Install dependencies
RUN npm ci

# Copy the rest of the application code
COPY . .

# Build the application
RUN npm run build

# Remove development dependencies
RUN npm prune --production

# Production stage
FROM node:18-alpine AS production

WORKDIR /app

# Set environment variables
ENV NODE_ENV=production

# Copy built application from build stage
COPY --from=build /app/dist ./dist
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package*.json ./
COPY --from=build /app/config ./config

# Create a non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S ingestor -u 1001 && \
    chown -R ingestor:nodejs /app

# Create directories for data and logs
RUN mkdir -p /app/data /app/logs && \
    chown -R ingestor:nodejs /app/data /app/logs

# Switch to non-root user
USER ingestor

# Expose the API port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD node -e "const http=require('http');const options={hostname:'localhost',port:3000,path:'/health',timeout:2000};const req=http.get(options,(res)=>{process.exit(res.statusCode === 200 ? 0 : 1)});req.on('error',()=>process.exit(1));req.end()"

# Start the application
CMD ["node", "dist/index.js"]