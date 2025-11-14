FROM node:22-alpine

# Install git, bash, and net-tools for port checking
RUN apk add --no-cache git bash net-tools

# Create app directory
WORKDIR /app

# Copy the startup script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Environment variables with defaults
ENV BRANCH=main
ENV CHECK_INTERVAL=60
ENV START_COMMAND="npm start"
ENV INSTALL_COMMAND="npm install"
ENV NODE_ENV=production

# Expose common Node.js port (can be overridden)
EXPOSE 3000

# Run the entrypoint script
ENTRYPOINT ["/entrypoint.sh"]
