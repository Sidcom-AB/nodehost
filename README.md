# Node.js Repo Hoster

A generic Docker image that can host and auto-update any Node.js application from a Git repository.

## Features

- 🚀 Host any Node.js app from a Git repository
- 🔄 Automatic updates when new commits are pushed
- ⚙️ Configurable via environment variables
- 🐳 Easy deployment with Docker Compose
- 📦 Uses latest Node.js LTS (Node 22)
- 🔒 Lightweight Alpine Linux base

## Quick Start

### Using Docker Compose (Recommended)

1. Create a `docker-compose.yml` file:

```yaml
version: '3.8'

services:
  my-app:
    image: ghcr.io/sidcom-ab/nodehost:latest
    container_name: my-node-app
    restart: unless-stopped
    environment:
      REPO_URL: https://github.com/yourusername/your-node-app.git
      BRANCH: main
      CHECK_INTERVAL: 60
      START_COMMAND: npm start
    ports:
      - "3000:3000"
    volumes:
      - app-data:/app/repo

volumes:
  app-data:
```

2. Start the container:

```bash
docker-compose up -d
```

### Using Docker CLI

```bash
docker run -d \
  --name my-node-app \
  -e REPO_URL=https://github.com/yourusername/your-node-app.git \
  -e BRANCH=main \
  -e CHECK_INTERVAL=60 \
  -p 3000:3000 \
  ghcr.io/sidcom-ab/nodehost:latest
```

### Using Portainer

1. Go to Stacks → Add Stack
2. Paste the docker-compose example above
3. Modify the environment variables for your app
4. Deploy!

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `REPO_URL` | ✅ Yes | - | The Git repository URL to clone and run |
| `BRANCH` | No | `main` | Git branch to track |
| `CHECK_INTERVAL` | No | `60` | How often to check for updates (in seconds) |
| `START_COMMAND` | No | `npm start` | Command to start your application |
| `INSTALL_COMMAND` | No | `npm install` | Command to install dependencies |
| `NODE_ENV` | No | `production` | Node.js environment |

## How It Works

1. **Initial Setup**: The container clones your Git repository and installs dependencies
2. **Start**: Your Node.js application is started using the specified command
3. **Monitoring**: Every `CHECK_INTERVAL` seconds, the container checks for new commits
4. **Auto-Update**: When a new commit is detected:
   - The current app is stopped
   - New code is pulled from Git
   - Dependencies are reinstalled
   - The app is restarted with the new code

## Examples

### Example 1: Express.js API

```yaml
services:
  express-api:
    image: ghcr.io/sidcom-ab/nodehost:latest
    environment:
      REPO_URL: https://github.com/mycompany/api.git
      BRANCH: production
      START_COMMAND: node server.js
      CHECK_INTERVAL: 120
    ports:
      - "8080:8080"
```

### Example 2: Next.js Application

```yaml
services:
  nextjs-app:
    image: ghcr.io/sidcom-ab/nodehost:latest
    environment:
      REPO_URL: https://github.com/mycompany/website.git
      BRANCH: main
      START_COMMAND: npm run start
      INSTALL_COMMAND: npm ci && npm run build
    ports:
      - "3000:3000"
```

### Example 3: Discord Bot

```yaml
services:
  discord-bot:
    image: ghcr.io/sidcom-ab/nodehost:latest
    environment:
      REPO_URL: https://github.com/mycompany/bot.git
      BRANCH: main
      START_COMMAND: node bot.js
      CHECK_INTERVAL: 300
    # No port mapping needed for Discord bots
```

## Private Repositories

To use private repositories, you can include credentials in the URL:

```yaml
environment:
  REPO_URL: https://username:token@github.com/mycompany/private-repo.git
```

Or use SSH keys by mounting them:

```yaml
volumes:
  - ~/.ssh:/root/.ssh:ro
environment:
  REPO_URL: git@github.com:mycompany/private-repo.git
```

## Viewing Logs

```bash
# Follow logs in real-time
docker logs -f my-node-app

# View last 100 lines
docker logs --tail 100 my-node-app
```

## Troubleshooting

### App doesn't start

- Check that your repository has a valid `package.json`
- Verify the `START_COMMAND` matches your app's start script
- Check logs for errors: `docker logs my-node-app`

### Port conflicts

- Make sure the port you're mapping is not already in use
- Adjust the port mapping in your docker-compose.yml

### Updates not working

- Verify the `CHECK_INTERVAL` is set correctly
- Check that your repository is accessible
- Ensure you're pushing to the correct branch

## Development

### Building the image locally

```bash
docker build -t nodehost:local .
```

### Testing locally

```bash
docker run -e REPO_URL=https://github.com/test/app.git nodehost:local
```

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## License

MIT

## Support

For issues and questions, please open an issue on [GitHub](https://github.com/Sidcom-AB/nodehost/issues).
