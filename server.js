const express = require('express');

const app = express();
const port = process.env.PORT || 8080;

app.get('/', (req, res) => {
  res.json({ message: 'Hello from the containerized app', version: process.env.APP_VERSION || 'dev' });
});

// Used by the load balancer / App Runner / Docker health checks
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

const server = app.listen(port, '0.0.0.0', () => {
  console.log(`Listening on port ${port}`);
});

// Shut down cleanly when ECS stops the container
process.on('SIGTERM', () => {
  server.close(() => process.exit(0));
});
