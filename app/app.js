const express = require('express');
const app = express();
const os = require('os');

const ENVIRONMENT_NAME = process.env.ENVIRONMENT_NAME || 'development'; // usar solo este
const VERSION = process.env.VERSION || '1.0.0';
const PORT = process.env.PORT || 3000;

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

app.get('/', (req, res) => {
    res.json({
        message: `¡Hola desde el ambiente ${ENVIRONMENT_NAME}!`,
        version: VERSION,
        timestamp: new Date().toISOString(),
        hostname: os.hostname(),
        status: 'activje',
        port: PORT
    });
});

app.get('/health', (req, res) => {
    res.status(200).json({ 
        status: 'OK', 
        environment: ENVIRONMENT_NAME,
        version: VERSION,
        uptime: process.uptime()
    });
});

module.exports = app;
