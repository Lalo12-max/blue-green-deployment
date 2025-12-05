const app = require('./app');

const PORT = process.env.PORT || 3000;
const ENVIRONMENT_NAME = process.env.ENVIRONMENT_NAME || 'development';
const VERSION = process.env.VERSION || '1.0.0';

app.listen(PORT, () => {
    console.log(`✅ Servidor producción iniciado en puerto ${PORT}, ambiente: ${ENVIRONMENT_NAME}, versión: ${VERSION}`);
});
