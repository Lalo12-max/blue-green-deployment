const express = require('express');
const app = express();
const os = require('os');

const ENVIRONMENT = process.env.ENVIRONMENT || 'development'; // dev / blue / green
const ENVIRONMENT_NAME = process.env.ENVIRONMENT_NAME || ENVIRONMENT; // blue/green
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
        status: 'active',
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

app.get('/api/users', (req, res) => {
    res.json({
        users: [
            { id: 1, name: 'Juan', role: 'admin' },
            { id: 2, name: 'María', role: 'user' },
            { id: 3, name: 'Carlos', role: 'user' }
        ],
        count: 3,
        environment: ENVIRONMENT_NAME
    });
});

app.post('/api/users', (req, res) => {
    const { name, role } = req.body;
    
    if (!name || !role) {
        return res.status(400).json({ 
            error: 'Nombre y rol son requeridos' 
        });
    }
    
    res.status(201).json({
        message: 'Usuario creado exitosamente',
        user: { id: Date.now(), name, role },
        environment: ENVIRONMENT_NAME
    });
});

app.get('/api/products', (req, res) => {
    res.json({
        products: [
            { id: 1, name: 'Producto A', price: 100 },
            { id: 2, name: 'Producto B', price: 200 },
            { id: 3, name: 'Producto C', price: 300 }
        ],
        environment: ENVIRONMENT_NAME
    });
});

app.use((req, res) => {
    res.status(404).json({ 
        error: 'Ruta no encontrada',
        path: req.path 
    });
});

module.exports = app;
