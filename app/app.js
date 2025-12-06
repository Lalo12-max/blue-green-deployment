const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

app.get('/', (req, res) => {
  res.json({
    message: `¡Hola desde el ambiente ${process.env.ENVIRONMENT_NAME || 'development'}!`,
    version: "1.0.0",
    timestamp: new Date(),
    hostname: require('os').hostname(),
    status: "active"
  });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port ${PORT}, environment: ${process.env.ENVIRONMENT_NAME || 'development'}`);
});
