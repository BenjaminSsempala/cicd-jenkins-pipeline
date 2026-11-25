const express = require('express');

const app = express();

app.get('/', (req, res) => {
  res.json({ message: 'Hello from the CI/CD pipeline!', version: process.env.APP_VERSION || 'dev' });
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

app.get('/add/:a/:b', (req, res) => {
  const a = Number(req.params.a);
  const b = Number(req.params.b);
  if (!Number.isInteger(a) || !Number.isInteger(b)) {
    return res.status(400).json({ error: 'a and b must be integers' });
  }
  res.json({ result: a + b });
});

module.exports = app;
