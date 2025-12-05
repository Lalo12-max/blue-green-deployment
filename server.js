const express = require('express');
const app = express();
const port = process.env.PORT || 3000;
const ENVIRONMENT = process.env.ENVIRONMENT || 'development';
const VERSION = process.env.VERSION || '1.0.0';

app.get('/', (req, res) => {
res.json({
message: ¡Hola desde el ambiente ${ENVIRONMENT}!,
version: VERSION,
timestamp: new Date().toISOString(),
hostname: require('os').hostname()
});
});

app.get('/health', (req, res) => {
res.status(200).json({ status: 'OK', environment: ENVIRONMENT });
});

app.get('/api/ping', (req, res) => {
res.json({ pong: true });
});

module.exports = app; // export para testing

if (require.main === module) {
app.listen(port, () => {
console.log(Servidor corriendo en puerto ${port}, ambiente: ${ENVIRONMENT});
});
}
