const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const bodyParser = require('body-parser');

const crypto = require('crypto');

// Inicializando o app Express
const app = express();
const port = process.env.PORT || 5000;

// Conexão com o MongoDB (com autenticação)
// Em produção (Cloud Run), usa a variável MONGODB_URI; localmente, usa o container Docker
const mongoURI = process.env.MONGODB_URI || 'mongodb://root:rootpassword@mongo-todo:27017/todo-app?authSource=admin';
mongoose.connect(mongoURI, {
  useNewUrlParser: true,
  useUnifiedTopology: true,
})
  .then(() => logger.info('Conectado ao MongoDB'))
  .catch((err) => logger.error('Erro ao conectar ao MongoDB:', err));

// CORS — restringir ao domínio do frontend em produção
// Em produção: https://frontend-seugrupo.dominio.com
// Em desenvolvimento: qualquer origem
const allowedOrigins = process.env.CORS_ORIGIN
  ? process.env.CORS_ORIGIN.split(',')
  : ['*'];

const corsOptions = {
  origin: allowedOrigins.includes('*') ? '*' : allowedOrigins,
  methods: ['GET', 'POST', 'PATCH', 'DELETE'],
  allowedHeaders: ['Content-Type'],
};

app.use(cors(corsOptions));
app.use(bodyParser.json());

const pino = require('pino');
const pinoHttp = require('pino-http');

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  formatters: {
    level: (label) => {
      return { level: label.toUpperCase() };
    },
  },
  timestamp: pino.stdTimeFunctions.isoTime,
});

app.use(pinoHttp({
  logger,
  customProps: (req, res) => {
    return {
      service: 'backend-api',
      environment: process.env.NODE_ENV || 'production',
      correlation_id: req.headers['x-correlation-id'] || crypto.randomUUID(),
      route: req.route ? req.route.path : req.originalUrl,
    };
  },
  customSuccessMessage: function (req, res) {
    return `HTTP ${req.method} ${req.url} completed`;
  },
  customErrorMessage: function (req, res, err) {
    return `HTTP ${req.method} ${req.url} failed`;
  }
}));

// Middleware auxiliar para capturar mensagens de erro antes de enviar a resposta
const sendError = (res, statusCode, message) => {
  res.locals.errorMessage = message;
  return res.status(statusCode).json({ message });
};


// Rota de health check (útil para o Load Balancer)
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

// Rota para simular erro 500 (Útil para testes de Observabilidade)
app.get('/api/force-error', (req, res) => {
  logger.error('Falha simulada acionada via /api/force-error');
  res.status(500).json({ error: 'Erro simulado para teste de observabilidade' });
});

// Definindo o modelo de Tarefa (To-do)
const TodoSchema = new mongoose.Schema({
  text: { type: String, required: true },
  completed: { type: Boolean, default: false },
});

const Todo = mongoose.model('Todo', TodoSchema);

// Rota para obter todas as tarefas (GET)
app.get('/todos', async (req, res) => {
  try {
    const todos = await Todo.find(); // Retorna todas as tarefas do banco
    res.json(todos);
  } catch (err) {
    sendError(res, 500, err.message);
  }
});

// Rota para adicionar uma nova tarefa (POST)
app.post('/todos', async (req, res) => {
  const { text } = req.body; // Obtém o texto da tarefa do corpo da requisição

  // Verifica se o campo "text" está presente
  if (!text) {
    return sendError(res, 400, 'O campo "text" é obrigatório');
  }

  const todo = new Todo({
    text,
    completed: false,
  });

  try {
    const newTodo = await todo.save(); // Salva a tarefa no banco
    res.status(201).json(newTodo); // Retorna a tarefa criada
  } catch (err) {
    sendError(res, 400, err.message); // Retorna erro se houver falha no banco de dados
  }
});

// Rota para marcar uma tarefa como concluída (PATCH)
app.patch('/todos/:id', async (req, res) => {
  try {
    const todo = await Todo.findById(req.params.id); // Encontra a tarefa pelo ID

    if (!todo) {
      return sendError(res, 404, 'Tarefa não encontrada');
    }

    // Alterna o status de "completed" da tarefa
    todo.completed = !todo.completed;
    await todo.save(); // Salva a tarefa modificada
    res.json(todo); // Retorna a tarefa atualizada
  } catch (err) {
    sendError(res, 500, err.message);
  }
});

// Rota para excluir uma tarefa (DELETE)
app.delete('/todos/:id', async (req, res) => {
  try {
    const todo = await Todo.findByIdAndDelete(req.params.id); // Deleta a tarefa pelo ID

    if (!todo) {
      return sendError(res, 404, 'Tarefa não encontrada');
    }

    res.json({ message: 'Tarefa excluída com sucesso' }); // Retorna uma mensagem de sucesso
  } catch (err) {
    sendError(res, 500, err.message);
  }
});

// Iniciando o servidor na porta configurada
app.listen(port, '0.0.0.0', () => {
  logger.info(`Servidor rodando na porta ${port}`);
});

