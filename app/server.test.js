const request = require('supertest');
const app = require("./app");

describe('API Endpoints', () => {
    // Test 1: Health check endpoint
    test('GET /health should return 200 and OK status', async () => {
        const response = await request(app)
            .get('/health')
            .expect('Content-Type', /json/)
            .expect(200);
        
        expect(response.body.status).toBe('OK');
        expect(response.body).toHaveProperty('environment');
        expect(response.body).toHaveProperty('uptime');
    });

    // Test 2: Root endpoint
    test('GET / should return welcome message', async () => {
        const response = await request(app)
            .get('/')
            .expect('Content-Type', /json/)
            .expect(200);
        
        expect(response.body).toHaveProperty('message');
        expect(response.body).toHaveProperty('version');
        expect(response.body).toHaveProperty('timestamp');
        expect(response.body).toHaveProperty('hostname');
        expect(response.body.status).toBe('active');
    });

    // Test 3: Users endpoint
    test('GET /api/users should return users array', async () => {
        const response = await request(app)
            .get('/api/users')
            .expect('Content-Type', /json/)
            .expect(200);
        
        expect(response.body).toHaveProperty('users');
        expect(Array.isArray(response.body.users)).toBe(true);
        expect(response.body.users.length).toBeGreaterThan(0);
        expect(response.body).toHaveProperty('count', 3);
        expect(response.body).toHaveProperty('environment');
    });

    // Test 4: Create user endpoint
    test('POST /api/users should create new user', async () => {
        const newUser = {
            name: 'Test User',
            role: 'tester'
        };
        
        const response = await request(app)
            .post('/api/users')
            .send(newUser)
            .expect('Content-Type', /json/)
            .expect(201);
        
        expect(response.body).toHaveProperty('message', 'Usuario creado exitosamente');
        expect(response.body.user).toHaveProperty('id');
        expect(response.body.user).toHaveProperty('name', 'Test User');
        expect(response.body.user).toHaveProperty('role', 'tester');
    });

    // Test 5: Products endpoint
    test('GET /api/products should return products', async () => {
        const response = await request(app)
            .get('/api/products')
            .expect('Content-Type', /json/)
            .expect(200);
        
        expect(response.body).toHaveProperty('products');
        expect(Array.isArray(response.body.products)).toBe(true);
        expect(response.body.products.length).toBeGreaterThan(0);
        expect(response.body.products[0]).toHaveProperty('id');
        expect(response.body.products[0]).toHaveProperty('name');
        expect(response.body.products[0]).toHaveProperty('price');
    });

    // Test 6: 404 handler
    test('GET non-existent route should return 404', async () => {
        const response = await request(app)
            .get('/non-existent-route')
            .expect('Content-Type', /json/)
            .expect(404);
        
        expect(response.body).toHaveProperty('error', 'Ruta no encontrada');
        expect(response.body).toHaveProperty('path', '/non-existent-route');
    });

    // Test 7: POST /api/users without required fields
    test('POST /api/users without required fields should return 400', async () => {
        const response = await request(app)
            .post('/api/users')
            .send({ name: 'Test' }) // Missing role
            .expect('Content-Type', /json/)
            .expect(400);
        
        expect(response.body).toHaveProperty('error', 'Nombre y rol son requeridos');
    });
});
