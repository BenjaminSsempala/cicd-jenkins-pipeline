const request = require('supertest');
const app = require('../src/app');

describe('app', () => {
  test('GET / returns a message', async () => {
    const res = await request(app).get('/');
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('message');
  });

  test('GET /health is ok', async () => {
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ status: 'ok' });
  });

  test('GET /add/2/3 returns 5', async () => {
    const res = await request(app).get('/add/2/3');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ result: 5 });
  });

  test('GET /add with non-integers is 400', async () => {
    const res = await request(app).get('/add/two/3');
    expect(res.status).toBe(400);
  });

  test('unknown route is 404', async () => {
    const res = await request(app).get('/nope');
    expect(res.status).toBe(404);
  });
});
