const express = require('express');
const app = express();
const port = process.env.PORT || 3000;
const ENVIRONMENT = process.env.ENVIRONMENT || 'development';
const VERSION = process.env.VERSION || '1.0.0';

// Middleware
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Endpoints principales
app.get('/', (req, res) => {
    res.json({
        message: `¡Hola desde el ambiente ${ENVIRONMENT}!`,
        version: VERSION,
        timestamp: new Date().toISOString(),
        hostname: require('os').hostname(),
        status: 'active'
    });
});

app.get('/health', (req, res) => {
    res.status(200).json({ 
        status: 'OK', 
        environment: ENVIRONMENT,
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
        environment: ENVIRONMENT
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
        environment: ENVIRONMENT
    });
});

app.get('/api/products', (req, res) => {
    res.json({
        products: [
            { id: 1, name: 'Producto A', price: 100 },
            { id: 2, name: 'Producto B', price: 200 },
            { id: 3, name: 'Producto C', price: 300 }
        ],
        environment: ENVIRONMENT
    });
});

// Manejo de errores
app.use((req, res, next) => {
    res.status(404).json({ 
        error: 'Ruta no encontrada',
        path: req.path 
    });
});

app.use((err, req, res, next) => {
    console.error(err.stack);
    res.status(500).json({ 
        error: 'Error interno del servidor',
        environment: ENVIRONMENT
    });
});

app.listen(port, () => {
    console.log(`✅ Servidor corriendo en puerto ${port}, ambiente: ${ENVIRONMENT}, versión: ${VERSION}`);
});
