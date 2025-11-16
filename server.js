const express = require('express');
const app = express();
const port = 3000;

const ENVIRONMENT = process.env.ENVIRONMENT || 'blue';

app.get('/', (req, res) => {
  res.json({
    message: `Bienvenido al ambiente ${ENVIRONMENT}`,
    environment: ENVIRONMENT,
    timestamp: new Date().toISOString(),
    version: process.env.VERSION || '1.0.0'
  });
});

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy', environment: ENVIRONMENT });
});

app.listen(port, '0.0.0.0', () => {
  console.log(`Servidor corriendo en puerto ${port}, ambiente: ${ENVIRONMENT}`);
});
