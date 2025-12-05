const app = require('./app');
const port = process.env.PORT || 3000;
const ENVIRONMENT = process.env.ENVIRONMENT || 'development';
const VERSION = process.env.VERSION || '1.0.0';

app.listen(port, () => {
    console.log(`✅ Servidor producción iniciado en puerto ${port}, ambiente: ${ENVIRONMENT}, versión: ${VERSION}`);
});
